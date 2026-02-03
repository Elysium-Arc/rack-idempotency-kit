# frozen_string_literal: true

require "json"
require "digest"
require "rack"
require "rack/idempotency/kit/version"

module Rack
  module Idempotency
    class Kit
      class Error < StandardError; end

      DEFAULT_TTL = 86_400
      DEFAULT_WAIT_TIMEOUT = 2
      DEFAULT_LOCK_TTL = 10
      DEFAULT_MAX_BODY_BYTES = 1_000_000

      def initialize(app, store:, ttl: DEFAULT_TTL, header: "Idempotency-Key", methods: %i[post put patch],
                     wait_timeout: DEFAULT_WAIT_TIMEOUT, lock_ttl: DEFAULT_LOCK_TTL,
                     max_body_bytes: DEFAULT_MAX_BODY_BYTES)
        @app = app
        @store = StoreAdapter.for(store)
        @ttl = ttl
        @header = header
        @methods = Array(methods).map { |m| m.to_s.downcase.to_sym }
        @wait_timeout = wait_timeout
        @lock_ttl = lock_ttl
        @max_body_bytes = max_body_bytes
      end

      def call(env)
        req = ::Rack::Request.new(env)
        method = req.request_method.downcase.to_sym
        return @app.call(env) unless @methods.include?(method)

        key = req.get_header(header_env_key)
        return @app.call(env) if key.nil? || key.strip.empty?

        fingerprint = fingerprint_for(req)
        stored = @store.read(key)
        return replay_or_conflict(key, stored, fingerprint) if stored

        unless @store.write_if_absent(key, { state: "in_flight", fingerprint: fingerprint }, ttl: @lock_ttl)
          stored = @store.read(key)
          return replay_or_conflict(key, stored, fingerprint) if stored
        end

        body = nil
        status, headers, body = @app.call(env)
        body_str = normalize_body(body)

        if body_str.bytesize <= @max_body_bytes
          record = {
            state: "completed",
            fingerprint: fingerprint,
            status: status,
            headers: headers,
            body: body_str
          }
          @store.write(key, record, ttl: @ttl)
        end

        [status, headers, [body_str]]
      ensure
        body&.close if body.respond_to?(:close)
      end

      private

      def header_env_key
        "HTTP_#{@header.upcase.tr('-', '_')}"
      end

      def fingerprint_for(req)
        body = req.body.read
        req.body.rewind
        Digest::SHA256.hexdigest([req.request_method, req.path, req.query_string, body].join("
"))
      end

      def replay_or_conflict(key, stored, fingerprint)
        if stored[:fingerprint] != fingerprint
          return [409, { "Content-Type" => "application/json" }, [JSON.dump(error: "idempotency_key_conflict")]]
        end

        if stored[:state] == "in_flight"
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @wait_timeout
          loop do
            sleep 0.05
            stored = @store.read(key)
            break unless stored && stored[:state] == "in_flight"
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          end
        end

        return [409, { "Content-Type" => "application/json" }, [JSON.dump(error: "idempotency_key_in_flight")]] if stored.nil? || stored[:state] == "in_flight"

        [stored[:status], stored[:headers], [stored[:body]]]
      end

      def normalize_body(body)
        if body.respond_to?(:each)
          chunks = []
          body.each { |part| chunks << part }
          chunks.join
        else
          body.to_s
        end
      end
    end

    class StoreAdapter
      def self.for(store)
        if store.respond_to?(:read) && store.respond_to?(:write)
          ActiveSupportAdapter.new(store)
        elsif store.respond_to?(:get) && store.respond_to?(:set)
          RedisAdapter.new(store)
        else
          raise Error, "store must support read/write or get/set"
        end
      end
    end

    class ActiveSupportAdapter
      def initialize(store)
        @store = store
      end

      def read(key)
        @store.read(storage_key(key))
      end

      def write(key, value, ttl:)
        @store.write(storage_key(key), value, expires_in: ttl)
      end

      def write_if_absent(key, value, ttl:)
        @store.write(storage_key(key), value, expires_in: ttl, unless_exist: true)
      end

      private

      def storage_key(key)
        "idempotency:#{key}"
      end
    end

    class RedisAdapter
      def initialize(redis)
        @redis = redis
      end

      def read(key)
        data = @redis.get(storage_key(key))
        data ? JSON.parse(data, symbolize_names: true) : nil
      end

      def write(key, value, ttl:)
        @redis.set(storage_key(key), JSON.dump(value), px: ttl * 1000)
      end

      def write_if_absent(key, value, ttl:)
        @redis.set(storage_key(key), JSON.dump(value), nx: true, px: ttl * 1000)
      end

      private

      def storage_key(key)
        "idempotency:#{key}"
      end
    end
  end
end
