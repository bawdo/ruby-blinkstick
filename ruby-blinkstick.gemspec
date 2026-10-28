# frozen_string_literal: true

require_relative "lib/blinkstick/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-blinkstick"
  spec.version = Blinkstick::VERSION
  spec.authors = ["Keith Bawden"]
  spec.email = ["keith@arrix.com.au"]

  spec.summary = "Drive BlinkStick Nano and Square USB LEDs from Ruby."
  spec.description = <<~DESC.tr("\n", " ").strip
    Drive BlinkStick Nano and Square USB LEDs from Ruby. Unofficial, and not
    affiliated with Agile Innovative. Releases before the implementation lands
    are placeholders that reserve the gem name.
  DESC
  spec.homepage = "https://github.com/bawdo/ruby-blinkstick"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "udev/*"] + %w[LICENSE README.md CHANGELOG.md CAPABILITIES.md]
  spec.require_paths = ["lib"]
end
