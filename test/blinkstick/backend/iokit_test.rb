# frozen_string_literal: true

require "test_helper"
require "rbconfig"

if RbConfig::CONFIG["host_os"].match?(/darwin/)
  # Required here, not at the top, so Linux never loads ffi.
  require "blinkstick/backend/iokit"

  # Only lists, loads and maps codes: nothing here writes to a stick.
  class IOKitTest < Minitest::Test
    IOKit = Blinkstick::Backend::IOKit
    SIGNED = 2**32

    TRANSFER_ERRORS = {
      0xE00002C5 => Blinkstick::BusyError,
      0xE00002C1 => Blinkstick::PermissionError,
      0xE00002E2 => Blinkstick::PermissionError,
      0xE00002C0 => Blinkstick::DisconnectedError,
      0xE00002D9 => Blinkstick::DisconnectedError,
      0xE00002CD => Blinkstick::Backend::TransferFailed,
      0xE00002BC => Blinkstick::Backend::TransferFailed
    }.freeze

    OPEN_ERRORS = {
      0xE00002C5 => Blinkstick::BusyError,
      0xE00002C1 => Blinkstick::PermissionError,
      0xE00002E2 => Blinkstick::PermissionError,
      0xE00002C0 => Blinkstick::NotFoundError,
      0xE00002D9 => Blinkstick::NotFoundError,
      0xE00002BC => Blinkstick::Error
    }.freeze

    def test_native_functions_resolve
      assert_respond_to IOKit::Native, :hid_manager_create
      assert_respond_to IOKit::Native, :hid_device_set_report
    end

    def test_list_without_sticks_is_empty_array
      devices = IOKit.new.list

      assert_kind_of Array, devices
      devices.each { |device| assert_device(device) }
    end

    def test_return_codes_map
      assert_maps(TRANSFER_ERRORS) { |code| IOKit.error_for(code) }
    end

    def test_open_return_codes_map
      assert_maps(OPEN_ERRORS) { |code| IOKit.open_error_for(code) }
    end

    def test_opens_shared
      assert_equal 0, IOKit::OPEN_OPTIONS
    end

    private

    # Checks the unsigned constant and the negative Integer ffi hands back
    # for the same kern_return_t.
    def assert_maps(table)
      table.each do |code, expected|
        [code, code - SIGNED].each do |value|
          assert_equal expected, yield(value), format("0x%<code>08X as %<value>d", code: code, value: value)
        end
      end
    end

    def assert_device(device)
      assert_instance_of Blinkstick::Backend::Device, device
      %i[serial manufacturer product].each { |field| assert_instance_of String, device.public_send(field) }
      assert_kind_of Integer, device.release
    end
  end
end
