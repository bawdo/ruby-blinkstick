# frozen_string_literal: true

require_relative "lib/blinkstick/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-blinkstick"
  spec.version = Blinkstick::VERSION
  spec.authors = ["Keith Bawden"]
  spec.email = ["keith@arrix.com.au"]

  spec.summary = "Drive BlinkStick Nano and Square USB LEDs from Ruby: names, effects and reconnect."
  spec.description = <<~DESC.tr("\n", " ").strip
    Find, open and drive BlinkStick Nano and Square USB LEDs from Ruby, on macOS
    and Linux. Sets every LED or one LED from hex, r,g,b or CSS colour names,
    reads them back, names a stick and opens it by name, writes the info blocks
    and mode, limits brightness, runs cancellable blink, pulse and morph
    effects, and reconnects after an unplug. Nothing to install but the gem.
    Unofficial, and not affiliated with Agile Innovative.
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

  spec.add_dependency "ffi", "~> 1.17", ">= 1.17.3"
end
