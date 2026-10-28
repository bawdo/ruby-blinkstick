# frozen_string_literal: true

if ENV["COVERAGE"] == "1"
  require "simplecov"
  require "simplecov-lcov"

  SimpleCov::Formatter::LcovFormatter.config do |c|
    c.report_with_single_file = true
    c.single_report_path = "coverage/lcov.info"
  end
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
    [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::LcovFormatter]
  )
  SimpleCov.start { add_filter "/test/" }
end

require "minitest/autorun"
require "blinkstick"
require "support/fake_backend"

# Every test starts with a backend that refuses to list or open, so a test
# that forgets FakeBackend::Installer fails loudly and never reaches the real
# stick. FakeBackend::Installer#teardown puts it back after each test.
Blinkstick::Backend.current = FakeBackend::REFUSING
