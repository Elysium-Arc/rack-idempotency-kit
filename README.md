# Rack Idempotency Kit

Stripe-style idempotency for Rack/Rails APIs.

## Install
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

## Behavior
- Replays stored responses for repeated idempotency keys
- Returns 409 if the same key is used with different request parameters

## Release
```bash
bundle exec rake release
```
