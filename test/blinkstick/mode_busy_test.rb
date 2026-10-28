# frozen_string_literal: true

require "test_helper"

# A real stick refuses transfers for 12 to 15 ms after a mode write. mode=
# waits that out under its lock instead of letting the next transfer fail.
class ModeBusyTest < Minitest::Test
  include FakeBackend::Installer

  SERIAL = "BS000002-3.1"

  def teardown
    @stick&.close
    super
  end

  def test_mode_waits_out_the_busy_window
    open_square(mode: 2, busy_after_mode: 4)
    @stick.mode = :ws2812_mirror

    assert_equal :ws2812_mirror, @stick.mode
    @stick.name = "x"
    @stick.write_info_block(2, "y")

    assert_equal "y".b, @stick.info_block(2)
    assert_equal 1, @backend.handles_for(SERIAL).size
  end

  def test_mode_gives_up_after_250_ms_when_the_stick_never_answers
    open_square(mode: 2, busy_after_mode: 1000)
    started = now
    assert_raises(Blinkstick::DisconnectedError) { @stick.mode = :ws2812_mirror }
    elapsed = now - started

    assert_operator elapsed, :>=, 0.25
    assert_operator elapsed, :<, 2.0
  end

  def test_mode_giving_up_names_the_stick_and_does_not_reconnect
    open_square(mode: 2, busy_after_mode: 1000)
    error = assert_raises(Blinkstick::DisconnectedError) { @stick.mode = :ws2812_mirror }

    assert_includes error.message, SERIAL.inspect
    assert_equal 1, @backend.handles_for(SERIAL).size
  end

  def test_unchanged_mode_does_not_wait
    open_square(mode: 3, busy_after_mode: 1000)
    started = now
    @stick.mode = :ws2812_mirror

    assert_operator now - started, :<, 0.1
    assert_empty handle.writes
    assert_equal 1, handle.attempts
  end

  private

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def open_square(**)
    @backend = install_backend(FakeBackend.new(FakeBackend.square(SERIAL), eeprom_writes: true, **))
    @stick = Blinkstick.open
  end

  def handle
    @backend.handles.fetch(0)
  end
end
