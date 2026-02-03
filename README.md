# Rack Idempotency Kit

[![Gem Version](https://img.shields.io/gem/v/rack-idempotency-kit.svg)](https://rubygems.org/gems/rack-idempotency-kit)
[![Gem Downloads](https://img.shields.io/gem/dt/rack-idempotency-kit.svg)](https://rubygems.org/gems/rack-idempotency-kit)
[![Ruby](https://img.shields.io/badge/ruby-3.0%2B-cc0000.svg)](https://www.ruby-lang.org)
[![CI](https://github.com/Elysium-Arc/rack-idempotency-kit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Elysium-Arc/rack-idempotency-kit/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/Elysium-Arc/rack-idempotency-kit.svg)](https://github.com/Elysium-Arc/rack-idempotency-kit/releases)
[![Rails](https://img.shields.io/badge/rails-6.x%20%7C%207.x%20%7C%208.x-cc0000.svg)](https://rubyonrails.org)
[![Elysium Arc](https://img.shields.io/badge/Elysium%20Arc-Reliability%20Toolkit-0b3d91.svg)](https://github.com/Elysium-Arc)

Stripe-style idempotency for Rack and Rails APIs.

## About
Rack Idempotency Kit ensures that repeated requests with the same idempotency key replay the original response instead of executing the action twice. It protects against retries, network timeouts, and client-side duplications.

The middleware stores a fingerprint of the request and a completed response. If the same key is used with different request parameters, it returns a conflict.

## Use Cases
- Payment, checkout, and webhook endpoints with retries
- API clients with timeouts and automatic replays
- Protecting side-effecting endpoints from duplicate writes
- Reducing p99 spikes caused by retry storms

## Compatibility
- Ruby 3.0+
- Rack 2.2+
- Works with Rails middleware stack

## Elysium Arc Reliability Toolkit
Also check out these related gems:
- Cache Coalescer: https://github.com/Elysium-Arc/cache-coalescer
- Cache SWR: https://github.com/Elysium-Arc/cache-swr
- Faraday Hedge: https://github.com/Elysium-Arc/faraday-hedge
- Env Contract: https://github.com/Elysium-Arc/env-contract

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
