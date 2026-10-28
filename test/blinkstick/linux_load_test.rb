# frozen_string_literal: true

require "test_helper"
require "English"
require "open3"
require "rbconfig"

class LinuxLoadTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  FIXTURES = File.join(ROOT, "test/fixtures/sysfs")

  FIXTURE_SCRIPT = <<~RUBY
    require "blinkstick"
    require "support/fake_backend"
    require "blinkstick/backend/hidraw"
    Blinkstick::Backend.current = Blinkstick::Backend::Hidraw.new(sysfs: ARGV.fetch(0))
    puts Blinkstick.list.map(&:serial).inspect
    fake = FakeBackend.new(FakeBackend.nano)
    Blinkstick::Backend.current = fake
    Blinkstick.open { |stick| stick.colour = :red }
    puts fake.handles.first.writes.size
    puts $LOADED_FEATURES.grep(%r{/ffi(\\.rb|/|_c)}).inspect
    puts defined?(FFI).inspect
  RUBY

  DEFAULT_SCRIPT = <<~RUBY
    require "blinkstick"
    puts Blinkstick.list.class
    puts $LOADED_FEATURES.grep(%r{/ffi(\\.rb|/|_c)}).inspect
    puts defined?(FFI).inspect
  RUBY

  def test_listing_through_hidraw_loads_no_ffi
    lines = run_ruby(FIXTURE_SCRIPT, FIXTURES)

    assert_equal ['["BS072777-3.0"]', "1", "[]", "nil"], lines
  end

  def test_default_backend_on_linux_loads_no_ffi
    skip "needs a Linux host" unless RbConfig::CONFIG["host_os"].match?(/linux/)

    assert_equal ["Array", "[]", "nil"], run_ruby(DEFAULT_SCRIPT)
  end

  private

  def run_ruby(script, *)
    out, err, status = Open3.capture3(RbConfig.ruby, "-I#{ROOT}/lib", "-I#{ROOT}/test", "-e", script, *)

    assert_predicate status, :success?, err
    out.lines(chomp: true)
  end
end
