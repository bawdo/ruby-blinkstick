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

  # Drives open and the handle against stubbed Native device calls, so no
  # test reaches IOKit or the stick attached to the machine.
  class IOKitHandleTest < Minitest::Test
    IOKit = Blinkstick::Backend::IOKit
    SIGNED = 2**32
    SERIAL = "BS000001-3.1"
    REPORT = ("\x06\x00".b + ("\x01".b * 24)).freeze
    NOT_ATTACHED = 0xE00002D9 - SIGNED

    # Every Native function that touches a device. Each test replaces all of
    # them, so a missed stub fails instead of reaching IOKit.
    DEVICE_CALLS = %i[hid_device_open hid_device_close hid_device_set_report].freeze

    WRITE_ERRORS = {
      NOT_ATTACHED => Blinkstick::DisconnectedError,
      0xE00002BC - SIGNED => Blinkstick::Backend::TransferFailed
    }.freeze

    OPEN_ERRORS = {
      0xE00002C5 => [Blinkstick::BusyError, "it is in use by another program"],
      0xE00002C1 => [Blinkstick::PermissionError, "permission denied"],
      0xE00002C0 => [Blinkstick::NotFoundError, "it is no longer attached"],
      0xE00002BC => [Blinkstick::Error, "the OS refused"]
    }.freeze

    def test_close_is_idempotent_and_never_raises
      calls = with_native(hid_device_close: NOT_ATTACHED) do
        handle = new_handle

        assert_nil handle.close
        assert_nil handle.close
      end

      assert_equal [[:hid_device_close, [ref, 0]]], calls
    end

    def test_write_after_close_raises_closed
      with_native(hid_device_close: 0) do
        handle = new_handle
        handle.close
        error = assert_raises(Blinkstick::ClosedError) { handle.write_feature(REPORT) }

        assert_includes error.message, SERIAL
      end
    end

    def test_write_passes_report_id_and_buffer
      calls = with_native(hid_device_set_report: 0) { new_handle.write_feature(REPORT) }

      assert_equal [[:hid_device_set_report, [ref, 2, 6, REPORT, 26]]], calls
    end

    def test_write_errors_map_and_name_the_serial
      WRITE_ERRORS.each do |code, expected|
        with_native(hid_device_set_report: code) do
          error = assert_raises(expected) { new_handle.write_feature(REPORT) }

          assert_equal "#{SERIAL}: writing a report failed (#{IOKit.describe(code)})", error.message
        end
      end
    end

    def test_open_returns_a_handle_on_the_listed_ref
      calls = with_native(hid_device_open: 0) do
        assert_instance_of IOKit::Handle, IOKit.new.open(device)
      end

      assert_equal [[:hid_device_open, [ref, 0]]], calls
    end

    def test_open_failures_map_with_a_reason
      OPEN_ERRORS.each do |code, (expected, reason)|
        with_native(hid_device_open: code - SIGNED) do
          error = assert_raises(expected) { IOKit.new.open(device) }

          assert_instance_of expected, error
          assert_equal "Could not open #{SERIAL}: #{reason} (#{IOKit.describe(code)})", error.message
        end
      end
    end

    private

    # A pointer that is never dereferenced: only stubs ever receive it.
    def ref
      @ref ||= FFI::Pointer.new(1)
    end

    def device
      Blinkstick::Backend::Device.new(id: ref, serial: SERIAL, manufacturer: "", product: "", release: 0x0201)
    end

    def new_handle
      IOKit::Handle.new(ref, serial: SERIAL)
    end

    # Replaces every device call on Native for the block and returns the
    # calls made. A call named in returns gives that value; any other fails.
    def with_native(returns)
      calls = []
      originals = DEVICE_CALLS.to_h { |name| [name, IOKit::Native.method(name)] }
      DEVICE_CALLS.each { |name| stub_call(name, returns, calls) }
      yield
      calls
    ensure
      originals&.each { |name, method| replace(name, method) }
    end

    def stub_call(name, returns, calls)
      replace(name) do |*args|
        calls << [name, args]
        returns.fetch(name) { raise Minitest::Assertion, "unexpected Native.#{name}" }
      end
    end

    # Removes the method first, so Ruby does not warn about redefining it.
    def replace(name, method = nil, &)
      IOKit::Native.singleton_class.remove_method(name)
      method ? IOKit::Native.define_singleton_method(name, method) : IOKit::Native.define_singleton_method(name, &)
    end
  end
end
