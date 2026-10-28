# frozen_string_literal: true

require "test_helper"
require "English"
require "rbconfig"

class LoadTest < Minitest::Test
  # Runs in a fresh process, so nothing earlier tests loaded can hide a leak.
  SCRIPT = <<~RUBY
    require "blinkstick"
    puts defined?(FFI).inspect
    puts Blinkstick.autoload?(:Backend).inspect
    puts $LOADED_FEATURES
  RUBY

  def test_require_loads_no_backend_and_no_ffi
    lib = File.expand_path("../../lib", __dir__)
    output = IO.popen([RbConfig.ruby, "-I#{lib}", "-e", SCRIPT], err: %i[child out], &:read)

    assert_predicate $CHILD_STATUS, :success?, output
    ffi, autoload, *features = output.lines(chomp: true)

    assert_equal ["nil", '"blinkstick/backend"'], [ffi, autoload], "FFI is defined, or Backend is not autoloaded"
    assert_empty features.grep(Regexp.union(%r{blinkstick/backend}, %r{/ffi(\.rb|/|_c)}))
  end
end
