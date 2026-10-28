# frozen_string_literal: true

require "test_helper"

# Shared by the reconnect tests below.
module ReconnectTestHelpers
  include FakeBackend::Installer

  Colour = Blinkstick::Colour
  Report = Blinkstick::Report

  SERIAL = "BS000002-3.1"

  RED = Colour.new(red: 255, green: 0, blue: 0)

  FRAME = Array.new(8) { |i| Colour.new(red: i + 1, green: 10 + i, blue: 20 + i) }.freeze

  # FRAME with LED 2 set to red.
  FRAME_RED_2 = FRAME.dup.tap { |frame| frame[2] = RED }.freeze

  def teardown
    @stick&.close
    super
  end

  private

  # Opens a Square with SERIAL, alongside any other devices given.
  def open_square(*others, **)
    @backend = install_backend(FakeBackend.new(FakeBackend.square(SERIAL), *others, **))
    @stick = Blinkstick.open(serial: SERIAL)
  end

  def unplug_and_replug(serial = SERIAL)
    @backend.unplug(serial)
    @backend.replug(serial)
  end

  def handles
    @backend.handles_for(SERIAL)
  end
end

# A replugged stick is found again and gets its last frame back.
class ReconnectTest < Minitest::Test
  include ReconnectTestHelpers

  def test_replug_repaints_last_frame
    stick = open_square
    stick.frame = FRAME
    unplug_and_replug

    mode = stick.mode
    first, second = handles

    assert_equal [:ws2812, true], [mode, first.closed?]
    assert_equal [[Report.frame(FRAME)], { Report::MODE_ID => 1 }], [second.writes, second.reads_by_id]
  end

  # The repaint sends the bytes last sent: limited once, flipped once.
  def test_repaint_sends_the_last_frame_as_it_was_sent
    stick = open_square
    stick.brightness_limit = 128
    stick.inverse = true
    stick.frame = FRAME
    unplug_and_replug

    stick.mode

    assert_equal handles.first.writes, handles.last.writes
  end

  def test_repaint_after_led_only_writes
    stick = open_square
    handles.first.leds = FRAME
    stick[2] = :red
    unplug_and_replug

    assert_equal FRAME_RED_2, stick.frame
    assert_equal [Report.frame(FRAME_RED_2)], handles.last.writes
  end

  # A failed LED write (report 5) is not a frame write, so the seeded frame
  # is repainted before the LED is written again.
  def test_failed_led_write_repaints_then_writes
    stick = open_square(fail_writes: 3)

    stick[0] = :red

    assert_equal [[], [Report.frame([Colour::OFF] * 8), Report.led(0, RED)]], handles.map(&:writes)
  end

  def test_no_repaint_before_a_frame_write
    stick = open_square
    stick.frame = FRAME
    unplug_and_replug

    stick.colour = :red

    assert_equal [Report.frame([RED] * 8)], handles.last.writes
  end

  def test_no_repaint_when_nothing_written
    stick = open_square
    unplug_and_replug

    assert_equal :ws2812, stick.mode
    assert_equal 2, handles.size
    assert_empty handles.last.writes
  end

  def test_still_unplugged_raises_then_recovers
    stick = open_square
    stick.frame = FRAME
    @backend.unplug(SERIAL)

    error = assert_raises(Blinkstick::DisconnectedError) { stick.mode }

    assert_equal %(could not reconnect: no BlinkStick with serial "#{SERIAL}"), error.message
    @backend.replug(SERIAL)

    assert_equal [:ws2812, 2, [Report.frame(FRAME)]], [stick.mode, handles.size, handles.last.writes]
  end

  def test_empty_reply_reconnects
    stick = open_square
    replies = 0
    handles.first.define_singleton_method(:read_feature) { |*| "".b.tap { replies += 1 } }

    assert_equal :ws2812, stick.mode
    assert_equal [3, 2], [replies, handles.size]
  end

  def test_finaliser_follows_new_handle
    procs = capture_finalisers do
      open_square
      unplug_and_replug
      @stick.mode
    end
    first, second = handles
    first.define_singleton_method(:close) { raise "the old handle's finaliser ran" }

    assert_equal 1, procs.size, "the old finaliser was not undefined"
    procs.last.call

    assert_predicate second, :closed?
  end

  private

  # Records the finalisers defined while the block runs instead of
  # registering them, and forgets them when one is undefined, as Ruby does.
  def capture_finalisers
    procs = []
    swap_finaliser_methods(define: ->(_object, callable) { procs << callable }, undefine: ->(_object) { procs.clear })
    yield
    procs
  ensure
    restore_finaliser_methods
  end

  def swap_finaliser_methods(define:, undefine:)
    space = ObjectSpace.singleton_class
    { define_finalizer: define, undefine_finalizer: undefine }.each do |name, body|
      space.alias_method(:"original_#{name}", name)
      space.remove_method(name)
      space.define_method(name, &body)
    end
  end

  def restore_finaliser_methods
    space = ObjectSpace.singleton_class
    %i[define_finalizer undefine_finalizer].each do |name|
      next unless space.method_defined?(:"original_#{name}")

      space.remove_method(name)
      space.alias_method(name, :"original_#{name}")
      space.remove_method(:"original_#{name}")
    end
  end
end

# Reconnecting that fails, or that must not be tried.
class ReconnectFailureTest < Minitest::Test
  include ReconnectTestHelpers

  def test_retry_fails_after_reconnect
    stick = open_square(fail_writes: 3)
    @backend.next_open(SERIAL, fail_writes: 3)

    assert_raises(Blinkstick::DisconnectedError) { stick.frame = FRAME }
    assert_equal 2, handles.size
    stick.frame = FRAME

    assert_equal [2, [Report.frame(FRAME)]], [handles.size, handles.last.writes]
  end

  def test_repaint_failure_drops_handle
    stick = replug_with_failing_repaint

    error = assert_raises(Blinkstick::DisconnectedError) { stick.mode }
    cause = %("#{SERIAL}" stopped responding: 3 writes failed in a row)

    assert_equal "reconnected, but repainting the last frame failed: #{cause}", error.message
    assert_predicate handles.last, :closed?
  end

  def test_repaint_failure_reopens_on_the_next_call
    stick = replug_with_failing_repaint
    assert_raises(Blinkstick::DisconnectedError) { stick.mode }

    assert_equal [:ws2812, 3], [stick.mode, handles.size]
    assert_equal [Report.frame(FRAME)], handles.last.writes
  end

  def test_reopen_refused_is_disconnected
    stick = open_square
    unplug_and_replug
    @backend.refuse(SERIAL, Blinkstick::BusyError)

    error = assert_raises(Blinkstick::DisconnectedError) { stick.mode }

    assert_includes error.message, "#{SERIAL} refused"
    assert_instance_of Blinkstick::BusyError, error.cause
  end

  def test_empty_serial_never_reconnects
    stick = open_blank
    unplug_and_replug("")

    error = assert_raises(Blinkstick::DisconnectedError) { stick.mode }

    assert_equal "could not reconnect: this stick has no serial, so it cannot be found again", error.message
    assert_equal [1, 1], [@backend.handles_for("").size, handles.size]
  end

  def test_ambiguous_serial_never_reconnects
    stick = open_square(FakeBackend.square(SERIAL).with(id: "fake:twin"))
    unplug_and_replug

    error = assert_raises(Blinkstick::DisconnectedError) { stick.mode }

    assert_includes error.message, %(serial "#{SERIAL}" is ambiguous: 2 sticks have it)
    assert_equal 1, handles.size
  end

  # The serial relists as a model the gem refuses, so it is never opened.
  def test_reconnect_refuses_an_unknown_model
    stick = open_square
    unplug_and_replug
    @backend.define_singleton_method(:list) { [FakeBackend.unknown(SERIAL)] }

    error = assert_raises(Blinkstick::DisconnectedError) { stick.mode }

    assert_instance_of Blinkstick::UnsupportedModelError, error.cause
    assert_equal 1, handles.size
  end

  def test_busy_and_permission_pass_through
    [Blinkstick::BusyError, Blinkstick::PermissionError, Blinkstick::ClosedError].each do |error_class|
      stick = open_square
      handles.first.define_singleton_method(:write_feature) { |_report| raise error_class, "from the handle" }

      error = assert_raises(error_class) { stick.colour = :red }

      assert_equal ["from the handle", 1], [error.message, handles.size]
      stick.close
    end
  end

  def test_close_while_disconnected
    stick = open_square
    @backend.unplug(SERIAL)
    assert_raises(Blinkstick::DisconnectedError) { stick.mode }

    stick.close
    stick.close

    assert_predicate stick, :closed?
    assert_predicate handles.first, :closed?
  end

  private

  # A frame written, the stick unplugged and replugged, and the reopened
  # handle failing every write, so the repaint fails.
  def replug_with_failing_repaint
    stick = open_square
    stick.frame = FRAME
    unplug_and_replug
    @backend.next_open(SERIAL, fail_writes: 3)
    stick
  end

  # An empty serial reads as an unknown model, so Blinkstick.open refuses it
  # first. This opens a Square beside a blank serial Nano and builds a Stick
  # for the Nano with the reopener Blinkstick would give it.
  def open_blank
    open_square(FakeBackend.nano("")).close
    blank = FakeBackend.nano("")
    info = Blinkstick::Info.from(serial: "", manufacturer: blank.manufacturer, product: blank.product,
                                 release: blank.release)
    @stick = Blinkstick::Stick.new(@backend.open(blank), info, reopen: Blinkstick.send(:reopener, ""))
  end
end

# A call reconnects at most once, even when it makes two transfers.
class ReconnectOncePerCallTest < Minitest::Test
  include ReconnectTestHelpers

  # The seeding read runs out and reconnects; the LED write then fails on
  # the new handle, which raises rather than reconnecting a second time.
  def test_led_write_after_a_reconnecting_seed_read
    stick = open_square(fail_reads: 3)
    @backend.next_open(SERIAL, fail_writes: 3)

    assert_raises(Blinkstick::DisconnectedError) { stick[2] = :red }
    assert_kept_new_handle
    stick[2] = :red

    assert_equal [2, [Report.led(2, RED)]], [handles.size, handles.last.writes]
  end

  # The same for mode=: its read of report 4 reconnects, then its write fails.
  def test_mode_write_after_a_reconnecting_mode_read
    stick = open_square(fail_reads: 3, eeprom_writes: true)
    @backend.next_open(SERIAL, fail_writes: 3)

    assert_raises(Blinkstick::DisconnectedError) { stick.mode = :ws2812_mirror }
    assert_kept_new_handle
    stick.mode = :ws2812_mirror

    assert_equal [2, [Report.mode(3)]], [handles.size, handles.last.writes]
  end

  private

  # Two handles, and the second still open: the Stick kept it.
  def assert_kept_new_handle
    assert_equal 2, handles.size
    refute_predicate handles.last, :closed?
    assert_predicate handles.first, :closed?
  end
end
