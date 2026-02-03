# Rack Idempotency Kit

Stripe-style idempotency for Rack and Rails APIs.

## About
Rack Idempotency Kit ensures that repeated requests with the same idempotency key replay the original response instead of executing the action twice. It protects against retries, network timeouts, and client-side duplications.

The middleware stores a fingerprint of the request and a completed response. If the same key is used with different request parameters, it returns a conflict.

## Compatibility
- Ruby 3.0+
- Rack 2.2+
- Works with Rails middleware stack

## Installation
```ruby
# Gemfile

gem "rack-idempotency-kit"
```

## Usage (Rails)
```ruby
# config/application.rb
config.middleware.use Rack::Idempotency::Kit,
  store: Rails.cache,
  ttl: 86_400,
  header: "Idempotency-Key"
```

## Usage (Rack)
```ruby
use Rack::Idempotency::Kit,
  store: MyStore.new,
  ttl: 86_400,
  header: "Idempotency-Key"
```

## Options
- `store` storage backend
- `ttl` (Integer) response retention in seconds
- `header` (String) idempotency header name
- `methods` (Array) HTTP methods to protect
- `wait_timeout` (Float) wait time for in-flight requests
- `lock_ttl` (Integer) in-flight lock TTL in seconds
- `max_body_bytes` (Integer) maximum body size to store

## Store Backends
- ActiveSupport cache stores (`read`/`write`)
- Redis-style stores (`get`/`set`)

## Behavior
- Replays stored responses for repeated idempotency keys
- Returns `409` if the same key is reused with a different request fingerprint
- Returns `409` if a request is still in flight after `wait_timeout`

## Release
```bash
bundle exec rake release
```
