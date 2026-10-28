# frozen_string_literal: true

require "test_helper"

# Shared by the read tests below. EEPROM writes need no check here: the fake
# refuses them with an error no test can rescue.
module ReadTestHelpers
  include FakeBackend::Installer

  Colour = Blinkstick::Colour
  Report = Blinkstick::Report

  SERIAL = "BS000002-3.1"

  FRAME = Array.new(8) { |i| Colour.new(red: i + 1, green: 10 + i, blue: 20 + i) }.freeze

  # Ten colours that differ in every channel.
  SHADES = Array.new(10) { |i| Colour.new(red: (i * 20) + 1, green: i, blue: 255 - i) }.freeze

  def teardown
    @stick&.close
    super
  end

  private

  # Opens a Square on a fresh fake, closing any stick this test opened before.
  def open_square(**)
    @stick&.close
    @backend = install_backend(FakeBackend.new(FakeBackend.square(SERIAL), **))
    @stick = Blinkstick.open
  end

  def handle
    @backend.handles.fetch(0)
  end
end

class ReadTest < Minitest::Test
  include ReadTestHelpers

  def test_frame_reads_back
    stick = open_square
    stick.frame = FRAME

    frame = stick.frame

    assert_equal FRAME, frame
    assert_predicate frame, :frozen?
  end

  def test_nano_frame_has_two_colours
    @backend = install_backend(FakeBackend.new(FakeBackend.nano))
    stick = @stick = Blinkstick.open

    assert_equal 2, stick.frame.size
    assert_raises(IndexError) { stick[2] }
    assert_equal({ Report::FRAME_ID => 1 }, handle.reads_by_id)
  end

  def test_led_reads_back
    stick = open_square
    stick.frame = FRAME

    assert_equal FRAME[5], stick[5]
  end

  def test_reads_are_never_cached
    stick = open_square
    stick.frame = FRAME

    stick.frame
    handle.leds = FRAME.reverse

    assert_equal FRAME.reverse, stick.frame
    assert_equal 2, handle.reads_by_id[Report::FRAME_ID]
  end

  def test_mode
    assert_equal :ws2812, open_square.mode
    assert_equal :ws2812_mirror, open_square(mode: 3).mode
    assert_equal 7, open_square(mode: 7).mode
  end

  def test_info_blocks
    stick = open_square(info_blocks: { 1 => "kitchen".b, 2 => "".b })

    assert_equal ["kitchen".b, "".b], [stick.info_block(1), stick.info_block(2)]
    assert_raises(ArgumentError) { stick.info_block(3) }
    assert_equal({ 2 => 1, 3 => 1 }, handle.reads_by_id)
  end

  def test_bad_info_block_numbers_send_nothing
    stick = open_square

    [0, -1, "1", nil].each { |n| assert_raises(ArgumentError) { stick.info_block(n) } }
    assert_equal 0, handle.attempts
  end

  def test_no_eeprom_writes
    stick = open_square
    stick.frame = FRAME

    [stick.frame, stick[0], stick.mode, stick.info_block(1), stick.info_block(2)]

    assert_equal({ Report::FRAME_ID => 2, Report::MODE_ID => 1, 2 => 1, 3 => 1 }, handle.reads_by_id)
    assert_equal({ Report::FRAME_ID => 1 }, handle.writes_by_id)
  end
end

class ReadFailureTest < Minitest::Test
  include ReadTestHelpers

  def test_reads_retry_transient_failures
    assert_equal FRAME, frame_after(fail_reads: 2)
    assert_equal 4, handle.attempts
    assert_raises(Blinkstick::DisconnectedError) { frame_after(fail_reads: 3) }
  end

  def test_failed_reads_name_the_serial
    stick = open_square(fail_reads: 3)

    error = assert_raises(Blinkstick::DisconnectedError) { stick.mode }

    assert_includes error.message, SERIAL
    assert_equal [Blinkstick::Backend::TransferFailed, 3], [error.cause.class, handle.attempts]
  end

  def test_short_and_wrong_id_reads_retry_then_disconnect
    %i[short_reads wrong_id_reads].each do |switch|
      assert_equal FRAME, frame_after(switch => 2), switch.to_s
      error = assert_raises(Blinkstick::DisconnectedError, switch.to_s) { frame_after(switch => 3) }
      assert_includes error.message, SERIAL
    end
  end

  def test_bad_replies_are_never_counted_as_reads
    assert_raises(Blinkstick::DisconnectedError) { open_square(short_reads: 3).info_block(1) }
    assert_equal 3, handle.attempts
    assert_empty handle.reads_by_id
  end

  def test_reads_from_a_gone_stick_are_not_retried
    stick = open_square(gone: true)

    assert_raises(Blinkstick::DisconnectedError) { stick.mode }
    assert_equal 1, handle.attempts
  end

  def test_reads_after_close
    stick = open_square
    stick.close

    [[:frame], [:[], 0], [:mode], [:info_block, 1]].each do |call|
      assert_raises(Blinkstick::ClosedError) { stick.public_send(*call) }
    end
    assert_equal 0, handle.attempts
  end

  def test_readers_and_writers_never_interleave
    frames = read_while_writing(open_square)

    assert_equal 250, frames.size
    frames.each { |frame| assert_equal [frame.first] * 8, frame, "a read saw two frames mixed" }
    assert_empty frames.map(&:first).uniq - SHADES
  end

  private

  def frame_after(**)
    stick = open_square(**)
    stick.frame = FRAME
    stick.frame
  end

  # Ten threads, 50 transfers each: even threads write uniform frames,
  # odd threads read. Writers cycle through the shades because the Mutex
  # is not fair: one writer can win every time, and a writer repeating one
  # colour could never produce a mixed frame.
  def read_while_writing(stick)
    stick.frame = [SHADES.first] * 8
    seen = Queue.new
    run_together(10) { |i, n| i.even? ? stick.frame = [SHADES[(i + n) % 10]] * 8 : seen << stick.frame }
    Array.new(seen.size) { seen.pop }
  end

  # Runs the block 50 times in each of count threads, held at a gate until
  # every thread exists so they overlap.
  def run_together(count)
    gate = Queue.new
    threads = Array.new(count) { |i| Thread.new { gate.pop && 50.times { |n| yield i, n } } }
    count.times { gate << true }
    threads.each(&:join)
  end
end
