# frozen_string_literal: true

require "test_helper"

class StickTest < Minitest::Test
  include FakeBackend::Installer

  Colour = Blinkstick::Colour
  Report = Blinkstick::Report

  RED = Colour.new(red: 255, green: 0, blue: 0)

  # Ten colours that differ in every channel, one per writer thread.
  SHADES = Array.new(10) { |i| Colour.new(red: (i * 20) + 1, green: i, blue: 255 - i) }.freeze
  SHADE_FRAMES = SHADES.map { |colour| Report.frame([colour] * 2) }.freeze

  def teardown
    @stick&.close
    super
  end

  def test_colour_writes_frame_for_model
    stick = open_stick(FakeBackend.nano)

    stick.colour = :red

    assert_equal [Report.frame([RED, RED])], handle.writes
  end

  def test_off_writes_zero_frame
    stick = open_stick(FakeBackend.square)

    stick.off

    assert_equal [Report.frame([Colour::OFF] * 8)], handle.writes
  end

  def test_colour_accepts_every_form
    stick = open_stick(FakeBackend.nano)

    ["#ff0000", [255, 0, 0], RED].each { |colour| stick.colour = colour }

    assert_equal [Report.frame([RED, RED])] * 3, handle.writes
  end

  def test_invalid_colour_raises_before_writing
    stick = open_stick(FakeBackend.nano)

    assert_raises(Blinkstick::InvalidColourError) { stick.colour = "not a colour" }
    assert_equal 0, handle.attempts
  end

  def test_use_after_close_raises_closed_error
    stick = open_stick(FakeBackend.nano)

    stick.close
    stick.close

    assert_raises(Blinkstick::ClosedError) { stick.colour = :red }
    assert_raises(Blinkstick::ClosedError) { stick.off }
    assert_equal [true, true, 0], [stick.closed?, handle.closed?, handle.attempts]
  end

  def test_new_stick_is_not_closed
    refute_predicate open_stick(FakeBackend.nano), :closed?
  end

  def test_retries_transient_failures
    stick = open_stick(FakeBackend.nano, fail_writes: 2)

    stick.colour = :red

    assert_equal 3, handle.attempts
    assert_equal [Report.frame([RED, RED])], handle.writes
  end

  def test_three_failures_raise_disconnected
    stick = open_stick(FakeBackend.nano, fail_writes: 3)

    error = assert_raises(Blinkstick::DisconnectedError) { stick.colour = :red }

    assert_includes error.message, "BS000001-3.0"
    assert_equal [Blinkstick::Backend::TransferFailed, Blinkstick::Backend::ATTEMPTS, []],
                 [error.cause.class, handle.attempts, handle.writes]
  end

  def test_gone_raises_disconnected_at_once
    stick = open_stick(FakeBackend.nano, gone: true)

    assert_raises(Blinkstick::DisconnectedError) { stick.colour = :red }
    assert_equal 1, handle.attempts
  end

  def test_concurrent_writers_never_interleave
    stick = open_stick(FakeBackend.nano)

    SHADES.map { |colour| Thread.new { 50.times { stick.colour = colour } } }.each(&:join)
    writes = handle.writes

    assert_equal 500, writes.size
    assert_empty writes - SHADE_FRAMES
    assert_equal 0, torn_frames, "frames interleaved on the wire"
  end

  private

  def open_stick(device, **)
    @backend = install_backend(FakeBackend.new(device, **))
    @stick = Blinkstick.open
  end

  def handle
    @backend.handles.fetch(0)
  end

  # Cuts the bytes, as they reached the device, into frame sized pieces and
  # counts the pieces that are not a whole frame of one shade.
  def torn_frames
    handle.stream.each_slice(Report::FRAME_SIZE).count { |bytes| !SHADE_FRAMES.include?(bytes.pack("C*")) }
  end
end
