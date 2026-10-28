# frozen_string_literal: true

require "test_helper"

class FakeBackendTest < Minitest::Test
  NANO = FakeBackend.nano
  SQUARE = FakeBackend.square
  FRAME = Blinkstick::Report.frame(Array.new(8, Blinkstick::Colour::OFF))
  READ = [Blinkstick::Report::FRAME_ID, Blinkstick::Report::FRAME_SIZE].freeze

  def test_eeprom_reports_raise_by_default
    handle = FakeBackend.new(NANO).open(NANO)

    [2, 3, 4].each do |id|
      assert_raises(FakeBackend::Handle::EepromWrite) { handle.write_feature([id].pack("C") + ("\0" * 32)) }
    end
    assert_empty handle.writes
  end

  def test_eeprom_writes_are_recorded_and_applied
    handle = FakeBackend.new(NANO, eeprom_writes: true).open(NANO)
    block = Blinkstick::Report.info_block(2, "hello")
    mode = Blinkstick::Report.mode(3)

    handle.write_feature(block)
    handle.write_feature(mode)

    assert_equal [block, mode], handle.writes
    assert_equal block, handle.read_feature(3, 33)
    assert_equal [4, 3].pack("C*"), handle.read_feature(4, 2)
  end

  def test_reads_default_to_mode_2_and_blank_blocks
    handle = FakeBackend.new(NANO).open(NANO)

    assert_equal [4, 2].pack("C*"), handle.read_feature(4, 2)
    assert_equal [3].pack("C") + ("\0" * 32), handle.read_feature(3, 33)
  end

  def test_constructor_mode_and_blocks_apply_to_every_device
    backend = FakeBackend.new(NANO, SQUARE, mode: 3, info_blocks: { 1 => "a".b, 2 => "b".b })

    [NANO, SQUARE].each do |device|
      handle = backend.open(device)

      assert_equal [4, 3].pack("C*"), handle.read_feature(4, 2)
      assert_equal "b", handle.read_feature(3, 33).byteslice(1, 1)
    end
  end

  def test_store_sets_one_device
    backend = FakeBackend.new(NANO, SQUARE)
    backend.store(SQUARE.serial, mode: 3, info_blocks: { 1 => "x".b, 2 => "y".b })
    square = backend.open(SQUARE)

    assert_equal [4, 2].pack("C*"), backend.open(NANO).read_feature(4, 2)
    assert_equal [4, 3].pack("C*"), square.read_feature(4, 2)
    assert_equal "x", square.read_feature(2, 33).byteslice(1, 1)
  end

  def test_eeprom_state_survives_reopening
    backend = FakeBackend.new(NANO, eeprom_writes: true)
    backend.open(NANO).write_feature(Blinkstick::Report.mode(3))

    assert_equal [4, 3].pack("C*"), backend.open(NANO).read_feature(4, 2)
  end

  def test_constructor_switches_apply_to_the_first_handle_only
    backend = FakeBackend.new(NANO, fail_writes: 3)
    first = backend.open(NANO)
    second = backend.open(NANO)

    assert_raises(Blinkstick::Backend::TransferFailed) { first.write_feature(FRAME) }
    second.write_feature(FRAME)

    assert_equal 1, second.writes.size
  end

  def test_first_handle_is_counted_per_device
    backend = FakeBackend.new(NANO, SQUARE, fail_writes: 1)

    assert_raises(Blinkstick::Backend::TransferFailed) { backend.open(NANO).write_feature(FRAME) }
    assert_raises(Blinkstick::Backend::TransferFailed) { backend.open(SQUARE).write_feature(FRAME) }
  end

  def test_next_open_queues_switches_for_one_open
    backend = FakeBackend.new(NANO)
    backend.open(NANO)
    backend.next_open(NANO.serial, fail_writes: 1)
    queued = backend.open(NANO)
    after = backend.open(NANO)

    assert_raises(Blinkstick::Backend::TransferFailed) { queued.write_feature(FRAME) }
    after.write_feature(FRAME)
  end
end

# Per device state: switches, unplugging, refusing and handle bookkeeping.
class FakeBackendDevicesTest < Minitest::Test
  NANO = FakeBackendTest::NANO
  SQUARE = FakeBackendTest::SQUARE
  FRAME = FakeBackendTest::FRAME
  READ = FakeBackendTest::READ

  def test_unplug_removes_from_list_and_goes_gone
    backend = FakeBackend.new(NANO, SQUARE)
    handle = backend.open(NANO)
    backend.unplug(NANO.serial)

    assert_equal [SQUARE], backend.list
    assert_raises(Blinkstick::DisconnectedError) { handle.write_feature(FRAME) }
    assert_raises(Blinkstick::DisconnectedError) { handle.read_feature(*READ) }
  end

  def test_replug_lists_again_and_old_handles_stay_gone
    backend = FakeBackend.new(NANO)
    old = backend.open(NANO)
    backend.unplug(NANO.serial)
    backend.replug(NANO.serial)

    assert_equal [NANO], backend.list
    assert_raises(Blinkstick::DisconnectedError) { old.read_feature(*READ) }
  end

  def test_replug_gives_dark_working_handles
    backend = FakeBackend.new(NANO)
    backend.open(NANO).leds = Array.new(8, Blinkstick::Colour.new(red: 255, green: 0, blue: 0))
    backend.unplug(NANO.serial)
    backend.replug(NANO.serial)
    fresh = backend.open(NANO)

    assert_equal Array.new(8, Blinkstick::Colour::OFF), fresh.leds
    fresh.write_feature(FRAME)
  end

  def test_refuse_raises_and_clears
    backend = FakeBackend.new(NANO)
    backend.refuse(NANO.serial, Blinkstick::BusyError)

    assert_raises(Blinkstick::BusyError) { backend.open(NANO) }
    backend.refuse(NANO.serial, nil)

    refute_nil backend.open(NANO)
  end

  def test_handles_for_is_in_open_order
    backend = FakeBackend.new(NANO, SQUARE)
    a = backend.open(NANO)
    backend.open(SQUARE)
    b = backend.open(NANO)

    assert_equal [a, b], backend.handles_for(NANO.serial)
    assert_empty FakeBackend.new(NANO).handles_for(NANO.serial)
  end

  # As hidraw does: the device node is gone (ENOENT or ENODEV).
  def test_open_of_an_unplugged_device_raises_not_found
    backend = FakeBackend.new(NANO)
    backend.unplug(NANO.serial)

    assert_raises(Blinkstick::NotFoundError) { backend.open(NANO) }
    backend.replug(NANO.serial)

    refute_nil backend.open(NANO)
  end

  def test_constructor_gone_applies_to_the_first_handle_only
    backend = FakeBackend.new(NANO, gone: true)
    first = backend.open(NANO)
    second = backend.open(NANO)

    assert_raises(Blinkstick::DisconnectedError) { first.write_feature(FRAME) }
    second.write_feature(FRAME)
  end

  def test_next_open_switches_merge_over_constructor_defaults_on_the_first_open
    backend = FakeBackend.new(NANO, fail_writes: 1)
    backend.next_open(NANO.serial, fail_reads: 1)
    first = backend.open(NANO)

    assert_raises(Blinkstick::Backend::TransferFailed) { first.write_feature(FRAME) }
    assert_raises(Blinkstick::Backend::TransferFailed) { first.read_feature(*READ) }
  end

  def test_unknown_serial_raises
    assert_raises(KeyError) { FakeBackend.new(NANO).unplug("nope") }
  end
end

# The LEDs live on the device, not the handle.
class FakeBackendLedsTest < Minitest::Test
  NANO = FakeBackendTest::NANO
  RED = Blinkstick::Colour.new(red: 255, green: 0, blue: 0)
  RED_FRAME = Blinkstick::Report.frame(Array.new(8, RED))
  READ = [Blinkstick::Report::FRAME_ID, Blinkstick::Report::FRAME_SIZE].freeze

  def test_leds_survive_a_reopen_without_unplug
    backend = FakeBackend.new(NANO)
    first = backend.open(NANO)
    first.write_feature(RED_FRAME)
    first.close

    assert_equal RED_FRAME, backend.open(NANO).read_feature(*READ)
  end

  def test_two_handles_on_one_serial_share_leds
    backend = FakeBackend.new(NANO)
    first = backend.open(NANO)
    second = backend.open(NANO)
    first.write_feature(Blinkstick::Report.led(3, RED))

    assert_equal RED, second.leds[3]
    assert_equal RED, Blinkstick::Report.decode_frame(second.read_feature(*READ), 8)[3]
  end

  def test_replug_starts_dark
    backend = FakeBackend.new(NANO)
    backend.open(NANO).write_feature(RED_FRAME)
    backend.unplug(NANO.serial)
    backend.replug(NANO.serial)

    assert_equal FakeBackendTest::FRAME, backend.open(NANO).read_feature(*READ)
  end
end

# The backend a test gets when it installs none.
class FakeBackendDefaultTest < Minitest::Test
  REFUSED = FakeBackend::Refusing::NoBackend

  # A stand in for a test class: Installer#teardown calls super.
  class Base
    def teardown; end
  end

  class Installing < Base
    include FakeBackend::Installer
  end

  def test_default_is_the_refusing_backend
    assert_same FakeBackend::REFUSING, Blinkstick::Backend.current
  end

  def test_refusing_backend_never_lists
    error = assert_raises(REFUSED) { Blinkstick.list }

    assert_match(/install_backend/, error.message)
  end

  def test_refusing_backend_never_opens
    assert_raises(REFUSED) { Blinkstick.open(serial: FakeBackendTest::NANO.serial) }
    assert_raises(REFUSED) { FakeBackend::REFUSING.open(FakeBackendTest::NANO) }
  end

  def test_refusal_is_not_a_blinkstick_error
    refute_operator REFUSED, :<, Blinkstick::Error
  end

  def test_installer_teardown_puts_the_refusing_backend_back
    installer = Installing.new
    installer.install_backend(FakeBackend.new)
    installer.teardown

    assert_same FakeBackend::REFUSING, Blinkstick::Backend.current
  end
end
