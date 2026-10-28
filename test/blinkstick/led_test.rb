# frozen_string_literal: true

require "test_helper"

class LedTest < Minitest::Test
  include FakeBackend::Installer

  Colour = Blinkstick::Colour
  Report = Blinkstick::Report

  RED = Colour.new(red: 255, green: 0, blue: 0)

  FRAME = Array.new(8) { |i| Colour.new(red: i + 1, green: 10 + i, blue: 20 + i) }.freeze

  # Ten colours that differ in every channel, one per writer thread.
  SHADES = Array.new(10) { |i| Colour.new(red: (i * 20) + 1, green: i, blue: 255 - i) }.freeze

  def teardown
    @stick&.close
    super
  end

  def test_set_one_led_sends_one_report5
    stick = open_stick(FakeBackend.square)

    stick[3] = :red

    assert_equal [Report.led(3, RED)], handle.writes
    assert_equal({ 5 => 1 }, handle.writes_by_id)
    assert_equal({ 6 => 1 }, handle.reads_by_id)
  end

  def test_assignment_returns_the_colour_argument
    stick = open_stick(FakeBackend.square)

    assert_equal :red, (stick[0] = :red)
  end

  def test_set_one_led_keeps_others
    stick = open_stick(FakeBackend.square)
    stick.frame = FRAME

    stick[3] = :red

    assert_equal FRAME.dup.tap { |colours| colours[3] = RED }, handle.leds
  end

  def test_set_one_led_with_bad_colour_sends_nothing
    stick = open_stick(FakeBackend.square)

    assert_raises(Blinkstick::InvalidColourError) { stick[0] = :notacolour }
    assert_equal 0, handle.attempts
  end

  def test_index_out_of_range
    stick = open_stick(FakeBackend.nano)

    [2, -1, "0"].each { |index| assert_raises(IndexError) { stick[index] = :red } }
    assert_equal 0, handle.attempts
  end

  def test_index_out_of_range_on_a_square
    stick = open_stick(FakeBackend.square)

    assert_raises(IndexError) { stick[8] = :red }
    assert_equal 0, handle.attempts
  end

  def test_set_after_close
    stick = open_stick(FakeBackend.nano)
    stick.close

    assert_raises(Blinkstick::ClosedError) { stick[0] = :red }
    assert_raises(Blinkstick::ClosedError) { stick.frame = %i[red red] }
    assert_equal 0, handle.attempts
  end

  def test_set_led_retries
    stick = open_stick(FakeBackend.nano, fail_writes: 2)

    stick[0] = :red

    assert_equal [Report.led(0, RED)], handle.writes
    assert_equal 4, handle.attempts, "one seeding read, then the write on its third attempt"
  end

  # The reopened handle fails too, so its repaint does: neither handle's
  # LEDs change.
  def test_failed_writes_leave_leds_untouched
    stick = open_stick(FakeBackend.nano, fail_writes: 3)
    @backend.next_open("BS000001-3.0", fail_writes: 3)

    assert_raises(Blinkstick::DisconnectedError) { stick[0] = :red }
    assert_equal([[[Colour::OFF] * 8, []]] * 2, @backend.handles.map { |h| [h.leds, h.writes] })
  end

  def test_concurrent_led_and_frame_writers_never_interleave
    stick = open_stick(FakeBackend.nano)

    run_together(stick)

    assert_equal 500, handle.writes.size
    assert_equal handle.writes, split_stream, "reports interleaved on the wire"
  end

  private

  # Starts every writer thread at once, behind a Queue gate.
  def run_together(stick)
    gate = Queue.new
    threads = SHADES.each_with_index.map do |colour, i|
      Thread.new { gate.pop and 50.times { write_one(stick, i, colour) } }
    end
    SHADES.size.times { gate << :go }
    threads.each(&:join)
  end

  def write_one(stick, thread, colour)
    thread.even? ? stick[thread % 2] = colour : stick.frame = [colour, colour]
  end

  def open_stick(device, **)
    @backend = install_backend(FakeBackend.new(device, **))
    @stick = Blinkstick.open
  end

  def handle
    @backend.handles.fetch(0)
  end

  # Cuts the wire bytes into reports, using each report's first byte for
  # its size, and checks the stream ends exactly on a report boundary.
  def split_stream
    sizes = { Report::LED_ID => Report::LED_SIZE, Report::FRAME_ID => Report::FRAME_SIZE }
    bytes = handle.stream.dup
    reports = []
    until bytes.empty?
      size = sizes[bytes.first] or flunk "unknown report ID #{bytes.first} on the wire"
      reports << bytes.shift(size).pack("C*")
    end
    reports
  end
end
