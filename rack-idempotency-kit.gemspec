# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rack/idempotency/kit/version"

Gem::Specification.new do |spec|
  spec.name = "rack-idempotency-kit"
  spec.version = Rack::Idempotency::Kit::VERSION
  spec.authors = ["MounirGaiby"]
  spec.email = ["mounirgaiby@gmail.com"]

  spec.summary = "Stripe-style idempotency middleware for Rack and Rails APIs."
  spec.description = "Provide idempotency keys with conflict detection and response replay."
  spec.homepage = "https://github.com/elysium-arc/rack-idempotency-kit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/elysium-arc/rack-idempotency-kit"
  spec.metadata["changelog_uri"] = "https://github.com/elysium-arc/rack-idempotency-kit/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rack", ">= 2.2"

  spec.add_development_dependency "bundler", ">= 1.17"
  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
