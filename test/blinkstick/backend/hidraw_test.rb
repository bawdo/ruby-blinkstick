# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require "blinkstick/backend/hidraw"

class HidrawTest < Minitest::Test
  Hidraw = Blinkstick::Backend::Hidraw
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

  def test_open_other_failures_raise_the_base_error
    Dir.mktmpdir do |dir|
      error = assert_raises(Blinkstick::Error) { Hidraw.new.open(device_at(dir)) }

      assert_instance_of Blinkstick::Error, error
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

# Reading goes through the same handle, with an io that fills the buffer.
class HidrawReadTest < Minitest::Test
  Hidraw = Blinkstick::Backend::Hidraw

  # Fills the buffer like the kernel does. It can also append a byte, as
  # Ruby's IO#ioctl may, so a caller trusting buffer.bytesize is caught out.
  class ReadIO
    attr_reader :calls

    def initialize(data, returns: data.bytesize, overflow: nil)
      @data = data
      @returns = returns
      @overflow = overflow
      @calls = []
    end

    def ioctl(request, buffer)
      @calls << [request, buffer.getbyte(0), buffer.bytesize]
      buffer[0, @data.bytesize] = @data
      buffer << @overflow if @overflow
      @returns
    end
  end

  def test_get_feature_request_codes
    assert_equal 0xC01A4807, Hidraw.get_feature_request(26)
    assert_equal 0xC0024807, Hidraw.get_feature_request(2)
    assert_equal 0xC0214807, Hidraw.get_feature_request(33)
  end

  def test_read_passes_request_and_buffer
    data = "\x06\x00".b + ("\x07".b * 24)
    io = ReadIO.new(data)
    result = Hidraw::Handle.new(io).read_feature(6, 26)

    assert_equal data, result
    assert_equal Encoding::BINARY, result.encoding
    assert_equal [[0xC01A4807, 6, 26]], io.calls
  end

  def test_read_slices_by_the_return_value_not_the_buffer_length
    data = "\x06\x00".b + ("\x07".b * 24)
    io = ReadIO.new(data, overflow: "\x00".b)

    assert_equal data, Hidraw::Handle.new(io).read_feature(6, 26)
  end

  def test_read_short
    io = ReadIO.new("\x06\x00".b + ("\x07".b * 24), returns: 10)

    assert_equal 10, Hidraw::Handle.new(io).read_feature(6, 26).bytesize
  end

  def test_read_nothing_returns_an_empty_binary_string
    result = Hidraw::Handle.new(ReadIO.new("".b, returns: 0)).read_feature(6, 26)

    assert_equal [0, Encoding::BINARY], [result.bytesize, result.encoding]
  end

  def test_read_errors_map
    HidrawTest::WRITE_ERRORS.each do |errno, expected|
      handle = Hidraw::Handle.new(HidrawTest::FakeIO.new(error: errno))
      assert_raises(expected, errno.name) { handle.read_feature(6, 26) }
    end
  end

  def test_read_feature_refuses_bad_arguments
    io = ReadIO.new("".b)
    handle = Hidraw::Handle.new(io)

    [[6, 0], [256, 26], [-1, 26], [6, -1], [6, "26"], ["6", 26], [nil, 26]].each do |id, size|
      assert_raises(ArgumentError) { handle.read_feature(id, size) }
    end

    assert_empty io.calls
  end

  def test_read_after_close
    handle = Hidraw::Handle.new(HidrawTest::FakeIO.new)
    handle.close

    assert_raises(Blinkstick::ClosedError) { handle.read_feature(6, 26) }
  end
end

# Listing reads sysfs only, so these run on any OS against fixtures.
class HidrawListTest < Minitest::Test
  Hidraw = Blinkstick::Backend::Hidraw
  ROOT = File.expand_path("../../..", __dir__)
  FIXTURES = File.expand_path("../../fixtures/sysfs", __dir__)

  # Lists the fixtures in a process whose default external encoding is
  # US-ASCII, where the keyboard's "Logitech® Keyboard" HID_NAME is not
  # valid text. It refuses to run under any other default, so the test
  # cannot pass just because the locale happens to be UTF-8.
  ASCII_LIST_SCRIPT = <<~RUBY
    abort "default_external is \#{Encoding.default_external}" unless Encoding.default_external == Encoding::US_ASCII
    require "blinkstick/backend/hidraw"
    puts Blinkstick::Backend::Hidraw.new(sysfs: ARGV.fetch(0)).list.map(&:serial).inspect
  RUBY

  def test_lists_only_blinksticks
    devices = Hidraw.new(sysfs: FIXTURES, dev: "/dev").list

    assert_equal [Blinkstick::Backend::Device.new(id: "/dev/hidraw0", serial: "BS072777-3.0",
                                                  manufacturer: "Agile Innovative Ltd", product: "BlinkStick",
                                                  release: 0x0202)], devices
  end

  def test_lists_under_an_ascii_locale_despite_non_ascii_names
    out, err, status = Open3.capture3({ "LC_ALL" => "C", "LANG" => "C" }, RbConfig.ruby, "-E", "US-ASCII:US-ASCII",
                                      "-I#{ROOT}/lib", "-e", ASCII_LIST_SCRIPT, FIXTURES)

    assert_predicate status, :success?, err
    assert_equal '["BS072777-3.0"]', out.chomp
  end

  def test_names_are_utf8_text_whatever_the_locale
    device = Hidraw.new(sysfs: FIXTURES, dev: "/dev").list.first

    [device.manufacturer, device.product, device.serial].each do |text|
      assert_equal [Encoding::UTF_8, true], [text.encoding, text.valid_encoding?]
    end
  end

  def test_lists_in_numeric_hidraw_order
    Dir.mktmpdir do |sysfs|
      [2, 10, 1].each { |number| fake_blinkstick(sysfs, number) }

      assert_equal %w[BS1 BS2 BS10], Hidraw.new(sysfs: sysfs, dev: "/dev").list.map(&:serial)
    end
  end

  # The USB IDs live once, on Blinkstick, so the backends cannot drift.
  def test_matches_on_the_gem_wide_usb_ids
    assert_empty Hidraw.constants(false) & %i[VENDOR_ID PRODUCT_ID]
  end

  def test_missing_sysfs_lists_nothing
    assert_empty Hidraw.new(sysfs: File.join(FIXTURES, "nowhere"), dev: "/dev").list
  end

  private

  # A hidrawN entry whose device is a BlinkStick with serial "BS<N>".
  def fake_blinkstick(sysfs, number)
    hid = File.join(sysfs, "devices/hid#{number}")
    FileUtils.mkdir_p(hid)
    File.write(File.join(hid, "uevent"), "HID_ID=0003:000020A0:000041E5\nHID_UNIQ=BS#{number}\n")
    entry = File.join(sysfs, "class/hidraw/hidraw#{number}")
    FileUtils.mkdir_p(entry)
    File.symlink(hid, File.join(entry, "device"))
  end
end
