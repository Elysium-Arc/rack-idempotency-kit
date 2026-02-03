# frozen_string_literal: true

require "rack/mock"
require "digest"

def fingerprint_for(method:, path:, query: "", body: "")
  Digest::SHA256.hexdigest([method, path, query, body].join("\n"))
end

RSpec.describe Rack::Idempotency::Kit do
  class MemoryStore
    attr_reader :writes

    def initialize
      @data = {}
      @writes = 0
    end

    def read(key)
      @data[key]
    end

    def write(key, value, expires_in: nil, unless_exist: false)
      return false if unless_exist && @data.key?(key)
      @data[key] = value
      @writes += 1
      true
    end
  end

  class RedisStore
    def initialize
      @data = {}
    end

    def get(key)
      @data[key]
    end

    def set(key, value, nx: false, px: nil)
      return false if nx && @data.key?(key)
      @data[key] = value
      true
    end
  end

  class UnknownStore; end

  it "passes through when method is not idempotent" do
    store = MemoryStore.new
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, ["ok"]] }

    middleware = described_class.new(app, store: store, methods: %i[post])
    req = Rack::MockRequest.new(middleware)

    res = req.get("/")
    expect(res.body).to eq("ok")
  end

  it "passes through when header is missing" do
    store = MemoryStore.new
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, ["ok"]] }

    middleware = described_class.new(app, store: store)
    req = Rack::MockRequest.new(middleware)

    res = req.post("/")
    expect(res.body).to eq("ok")
  end

  it "replays responses for the same idempotency key" do
    store = MemoryStore.new
    counter = 0
    app = lambda do |_env|
      counter += 1
      [200, { "Content-Type" => "text/plain" }, ["ok-#{counter}"]]
    end

    middleware = described_class.new(app, store: store)
    req = Rack::MockRequest.new(middleware)

    res1 = req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc")
    res2 = req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc")

    expect(res1.body).to eq("ok-1")
    expect(res2.body).to eq("ok-1")
  end

  it "returns conflict when the same key is reused with different params" do
    store = MemoryStore.new
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, ["ok"]] }

    middleware = described_class.new(app, store: store)
    req = Rack::MockRequest.new(middleware)

    req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc", input: "a")
    res2 = req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc", input: "b")

    expect(res2.status).to eq(409)
  end

  it "returns conflict when request is still in flight" do
    store = MemoryStore.new
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, ["ok"]] }

    middleware = described_class.new(app, store: store, wait_timeout: 0.01)
    req = Rack::MockRequest.new(middleware)

    store.write("idempotency:abc", { state: "in_flight", fingerprint: fingerprint_for(method: "POST", path: "/") })
    res = req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc")

    expect(res.status).to eq(409)
  end

  it "waits for in-flight request to complete" do
    store = MemoryStore.new
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, ["ok"]] }

    middleware = described_class.new(app, store: store, wait_timeout: 0.05)
    req = Rack::MockRequest.new(middleware)

    call_count = 0
    fp = fingerprint_for(method: "POST", path: "/")
    store.define_singleton_method(:read) do |key|
      call_count += 1
      return { state: "in_flight", fingerprint: fp } if call_count < 2
      { state: "completed", fingerprint: fp, status: 200, headers: { "Content-Type" => "text/plain" }, body: "done" }
    end

    res = req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc")
    expect(res.body).to eq("done")
  end

  it "does not store responses larger than max_body_bytes" do
    store = MemoryStore.new
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, ["too-large"]] }

    middleware = described_class.new(app, store: store, max_body_bytes: 2)
    req = Rack::MockRequest.new(middleware)

    req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc")

    expect(store.writes).to eq(1) # only the in-flight write
  end

  it "replays from pre-existing records when write_if_absent fails" do
    store = MemoryStore.new
    store.write("idempotency:abc", { state: "completed", fingerprint: fingerprint_for(method: "POST", path: "/"), status: 200, headers: {}, body: "cached" })
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, ["ok"]] }

    middleware = described_class.new(app, store: store)
    req = Rack::MockRequest.new(middleware)

    res = req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc")
    expect(res.body).to eq("cached")
  end

  it "normalizes bodies without #each" do
    store = MemoryStore.new
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, Object.new] }
    middleware = described_class.new(app, store: store)

    body = middleware.send(:normalize_body, "string-body")
    expect(body).to eq("string-body")
  end

  it "closes bodies that respond to close" do
    store = MemoryStore.new
    body = Class.new do
      attr_reader :closed

      def initialize
        @closed = false
      end

      def each
        yield "ok"
      end

      def close
        @closed = true
      end
    end.new

    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, body] }
    middleware = described_class.new(app, store: store)
    req = Rack::MockRequest.new(middleware)

    req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc")
    expect(body.closed).to eq(true)
  end

  it "supports redis-style stores" do
    store = RedisStore.new
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, ["ok"]] }

    middleware = described_class.new(app, store: store)
    req = Rack::MockRequest.new(middleware)

    res1 = req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc")
    res2 = req.post("/", "HTTP_IDEMPOTENCY_KEY" => "abc")

    expect(res1.body).to eq("ok")
    expect(res2.body).to eq("ok")
  end

  it "raises for unknown store adapters" do
    app = lambda { |_env| [200, { "Content-Type" => "text/plain" }, ["ok"]] }
    expect { described_class.new(app, store: UnknownStore.new) }.to raise_error(Rack::Idempotency::Kit::Error)
  end
end
