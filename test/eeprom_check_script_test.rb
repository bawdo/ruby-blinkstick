# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# Runs scripts/eeprom-check.rb with argument sets that must be refused. The
# script checks its arguments before it loads the gem or any backend, so none
# of these runs can reach a device. Never add a case with both a serial and
# --yes-write-eeprom: that would write a real stick.
class EepromCheckScriptTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/eeprom-check.rb", __dir__)

  def test_no_arguments_is_refused
    assert_refused([])
  end

  def test_serial_only_is_refused
    assert_refused(["BS000000-3.0"])
  end

  def test_flag_only_is_refused
    assert_refused(["--yes-write-eeprom"])
  end

  def test_flag_first_with_no_serial_is_refused
    assert_refused(["--yes-write-eeprom", "--yes-write-eeprom"])
  end

  def test_unknown_flag_is_refused
    assert_refused(["BS000000-3.0", "--yes"])
  end

  def test_extra_arguments_are_refused
    assert_refused(["BS000000-3.0", "BS000001-3.0", "--yes"])
  end

  private

  def assert_refused(args)
    out, err, status = Open3.capture3(RbConfig.ruby, SCRIPT, *args)

    assert_equal 2, status.exitstatus, "exit status for #{args.inspect}"
    assert_match(/usage/i, err)
    assert_empty out
  end
end
