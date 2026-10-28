# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "blinkstick/backend/hidraw"

class HidrawTest < Minitest::Test
  Hidraw = Blinkstick::Backend::Hidraw
  FIXTURES = File.expand_path("../../fixtures/sysfs", __dir__)
  REQUEST = 0xC01A4806
  REPORT = ("\x06\x00".b + ("\x01".b * 24)).freeze

  WRITE_ERRORS = {
    Errno::ENODEV => Blinkstick::DisconnectedError,
    Errno::ENOENT => Blinkstick::DisconnectedError,
    Errno::ESHUTDOWN => Blinkstick::DisconnectedError,
    Errno::EACCES => Blinkstick::PermissionError,
    Errno::EPERM => Blinkstick::PermissionError,
    Errno::EIO => Blinkstick::Backend::TransferFailed
  }.freeze

  # Records what it was asked to do, or fails the way the kernel would.
  class FakeIO
    attr_reader :calls, :closes

    def initialize(error: nil, close_error: nil)
      @error = error
      @close_error = close_error
      @calls = []
      @closes = 0
    end

    def ioctl(request, buffer)
      @calls << [request, buffer]
      raise @error if @error

      0
    end

    def close
      @closes += 1
      raise @close_error if @close_error
    end
  end

  def test_lists_only_blinksticks
    devices = Hidraw.new(sysfs: FIXTURES, dev: "/dev").list

    assert_equal [Blinkstick::Backend::Device.new(id: "/dev/hidraw0", serial: "BS072777-3.0",
                                                  manufacturer: "Agile Innovative Ltd", product: "BlinkStick",
                                                  release: 0x0202)], devices
  end

  def test_missing_sysfs_lists_nothing
    assert_empty Hidraw.new(sysfs: File.join(FIXTURES, "nowhere"), dev: "/dev").list
  end

  def test_ioctl_request_codes
    assert_equal REQUEST, Hidraw.set_feature_request(26)
  end

  def test_open_vanished_device_raises_not_found
    device = device_at("/nonexistent/hidraw9")
    error = assert_raises(Blinkstick::NotFoundError) { Hidraw.new.open(device) }
    assert_includes error.message, "BS072777-3.0"
  end

  def test_open_without_permission_points_at_udev_rule
    skip "root can open any file" if Process.uid.zero?

    Dir.mktmpdir do |dir|
      path = File.join(dir, "hidraw0")
      File.write(path, "")
      File.chmod(0o000, path)
      error = assert_raises(Blinkstick::PermissionError) { Hidraw.new.open(device_at(path)) }
      assert_includes error.message, "udev"
      assert_includes error.message, "BS072777-3.0"
    end
  end

  def test_open_returns_a_working_handle
    Dir.mktmpdir do |dir|
      path = File.join(dir, "hidraw0")
      File.write(path, "")
      handle = Hidraw.new.open(device_at(path))

      assert_instance_of Hidraw::Handle, handle
      handle.close
    end
  end

  def test_write_passes_request_and_report
    io = FakeIO.new
    Hidraw::Handle.new(io).write_feature(REPORT)

    assert_equal [[REQUEST, REPORT]], io.calls
  end

  def test_write_does_not_hand_over_the_callers_string
    io = FakeIO.new
    Hidraw::Handle.new(io).write_feature(REPORT)

    refute_same REPORT, io.calls.first.last
  end

  def test_write_errors_map
    WRITE_ERRORS.each do |errno, expected|
      handle = Hidraw::Handle.new(FakeIO.new(error: errno))
      assert_raises(expected, errno.name) { handle.write_feature(REPORT) }
    end
  end

  def test_write_after_close_raises_closed
    handle = Hidraw::Handle.new(FakeIO.new)
    handle.close

    assert_raises(Blinkstick::ClosedError) { handle.write_feature(REPORT) }
  end

  def test_close_is_idempotent_and_never_raises
    io = FakeIO.new(close_error: IOError)
    handle = Hidraw::Handle.new(io)
    handle.close
    handle.close

    assert_equal 1, io.closes
  end

  def test_close_swallows_system_call_errors
    Hidraw::Handle.new(FakeIO.new(close_error: Errno::EIO)).close
  end

  private

  def device_at(path)
    Blinkstick::Backend::Device.new(id: path, serial: "BS072777-3.0", manufacturer: "", product: "", release: 0x0202)
  end
end
