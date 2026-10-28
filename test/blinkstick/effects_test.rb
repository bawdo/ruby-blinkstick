# frozen_string_literal: true

require "test_helper"

# What the effects tests share: an opened Nano, a FakeCancel and frame helpers.
module EffectsHelpers
  include FakeBackend::Installer

  Colour = Blinkstick::Colour
  Report = Blinkstick::Report

  RED = Colour.new(red: 255, green: 0, blue: 0)
  OFF = Colour::OFF

  # Stands in for Cancellation: records waits, never sleeps, and reports
  # cancelled on the wait numbered cancel_on (1 based) or once #cancel is called.
  class FakeCancel
    attr_reader :waits

    def initialize(cancel_on: nil, cancelled: false)
      @cancel_on = cancel_on
      @cancelled = cancelled
      @waits = []
    end

    def cancelled?
      @cancelled
    end

    def wait(seconds)
      @waits << seconds
      @cancelled = true if @cancel_on == @waits.size
      @cancelled
    end
  end

  # Reports cancelled once the handle holds the given number of writes,
  # never from wait, so only the per step check can stop an effect.
  class CancelAfterWrites < FakeCancel
    def initialize(handle, writes)
      super()
      @handle = handle
      @writes = writes
    end

    def cancelled?
      @handle.writes.size >= @writes
    end
  end

  def teardown
    @stick&.close
    super
  end

  private

  def open_stick
    @backend = install_backend(FakeBackend.new(FakeBackend.nano))
    @stick = Blinkstick.open
  end

  def handle
    @backend.handles.fetch(0)
  end

  def frame_of(colour)
    Report.frame([colour, colour])
  end

  # Frames with both Nano LEDs at each red value.
  def reds(*values)
    values.map { |value| frame_of(red_of(value)) }
  end

  def red_of(value)
    Colour.new(red: value, green: 0, blue: 0)
  end

  # Lights the stick with one red value and forgets the write.
  def light(value)
    @stick.colour = red_of(value)
    handle.writes.clear
  end
end

class BlinkTest < Minitest::Test
  include EffectsHelpers

  def setup
    open_stick
    @cancel = FakeCancel.new
  end

  def test_blink_sequence
    assert @stick.blink(RED, period: 1, repeats: 2, cancel: @cancel)
    assert_equal [frame_of(RED), frame_of(OFF), frame_of(RED), frame_of(OFF)], handle.writes
  end

  def test_blink_waits_and_ends_off
    @stick.blink(RED, period: 1, repeats: 2, cancel: @cancel)

    assert_equal [0.5] * 4, @cancel.waits
    assert_equal [OFF, OFF], handle.leds.first(2)
  end

  def test_cancel_during_wait_stops
    cancel = FakeCancel.new(cancel_on: 2)

    refute @stick.blink(RED, period: 1, repeats: 3, cancel:)
    assert_equal [frame_of(RED), frame_of(OFF)], handle.writes
  end

  def test_cancel_before_start_sends_nothing
    before = handle.attempts

    refute @stick.blink(RED, period: 1, cancel: FakeCancel.new(cancelled: true))
    assert_equal before, handle.attempts
  end

  def test_nil_cancel_runs_to_the_end
    assert @stick.blink(RED, period: 0.02)
    assert_equal [frame_of(RED), frame_of(OFF)], handle.writes
  end

  def test_real_cancellation_from_another_thread
    cancel = Blinkstick::Cancellation.new
    canceller = cancel_after_first_write(cancel)

    result, elapsed = timed { @stick.blink(RED, period: 2, cancel:) }
    canceller.join

    refute result
    assert_operator elapsed, :<, 0.5
    assert_equal 1, handle.writes.size
  end

  private

  # Cancels only once the first write has landed (bounded at 2 s), however slow
  # the main thread is.
  def cancel_after_first_write(cancel)
    Thread.new do
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      sleep 0.005 while handle.writes.empty? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      cancel.cancel
    end
  end

  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
  end
end

class PulseTest < Minitest::Test
  include EffectsHelpers

  def setup
    open_stick
    @cancel = FakeCancel.new
  end

  def test_pulse_sequence
    assert @stick.pulse(RED, duration: 0.1, cancel: @cancel)
    assert_equal [frame_of(OFF), *reds(127, 255, 128, 0)], handle.writes
  end

  def test_pulse_waits_between_steps_and_ends_off
    @stick.pulse(RED, duration: 0.1, cancel: @cancel)

    assert_equal [0.02, 0.02], @cancel.waits
    assert_equal [OFF, OFF], handle.leds.first(2)
  end

  def test_pulse_repeats
    @stick.pulse(RED, duration: 0.1, repeats: 2, cancel: @cancel)

    assert_equal 10, handle.writes.size
  end

  def test_cancel_before_start_sends_nothing
    before = handle.attempts

    refute @stick.pulse(RED, duration: 1, cancel: FakeCancel.new(cancelled: true))
    assert_equal before, handle.attempts
  end
end

class MorphTest < Minitest::Test
  include EffectsHelpers

  def setup
    open_stick
    @cancel = FakeCancel.new
  end

  def test_morph_steps_and_lerp
    light(200)

    assert @stick.morph(OFF, duration: 0.06, cancel: @cancel)
    assert_equal reds(134, 67, 0), handle.writes
  end

  def test_morph_waits_between_steps_only
    light(200)
    @stick.morph(OFF, duration: 0.06, cancel: @cancel)

    assert_equal [0.02, 0.02], @cancel.waits
  end

  def test_morph_step_count_follows_go
    assert_equal 29, morph_frames(0.58)
    assert_equal 3, morph_frames(0.06)
  end

  def test_morph_under_one_step_jumps
    assert @stick.morph(RED, duration: 0, cancel: @cancel)
    assert_equal [frame_of(RED)], handle.writes
    assert_empty @cancel.waits
  end

  def test_morph_scales_target_once
    @stick.brightness_limit = 128
    @stick.morph(RED, duration: 0.04, cancel: @cancel)

    assert_equal reds(64, 128), handle.writes
    assert_equal [red_of(128)] * 2, handle.leds.first(2)
  end

  def test_morph_from_frame_under_inverse
    @stick.inverse = true
    light(200)
    @stick.morph(OFF, duration: 0.06, cancel: @cancel)

    # Written flipped (255 minus the value), read back unflipped.
    written = handle.writes.map { |report| report.getbyte(3) }

    assert_equal [121, 188, 255], written
    assert_equal [OFF, OFF], @stick.frame.first(2)
  end

  def morph_frames(duration)
    handle.writes.clear
    @stick.morph(RED, duration:, cancel: @cancel)
    handle.writes.size
  end

  def test_cancel_before_start_sends_nothing
    before = handle.attempts

    refute @stick.morph(RED, duration: 1, cancel: FakeCancel.new(cancelled: true))
    assert_equal before, handle.attempts
  end

  def test_cancel_between_steps_stops_before_the_next_write
    light(200)

    cancel = CancelAfterWrites.new(handle, 1)

    refute @stick.morph(OFF, duration: 0.06, cancel:)
    assert_equal [reds(134), [0.02]], [handle.writes, cancel.waits]
  end

  def test_cancel_during_morph_leaves_leds_as_they_are
    refute @stick.morph(RED, duration: 0.1, cancel: FakeCancel.new(cancel_on: 1))
    assert_equal reds(51), handle.writes
    assert_equal [red_of(51)] * 2, handle.leds.first(2)
  end
end

class EffectArgumentsTest < Minitest::Test
  include EffectsHelpers

  BAD_TIMES = [0, -1, Float::INFINITY, Float::NAN, "1", nil].freeze
  BAD_REPEATS = [0, -1, 1.5, "1", nil].freeze

  def setup
    open_stick
    @cancel = FakeCancel.new
  end

  def test_bad_period
    BAD_TIMES.each { |period| assert_raises(ArgumentError) { @stick.blink(RED, period:, cancel: @cancel) } }
    refute_sent
  end

  def test_bad_pulse_duration
    BAD_TIMES.each { |duration| assert_raises(ArgumentError) { @stick.pulse(RED, duration:, cancel: @cancel) } }
    refute_sent
  end

  def test_bad_morph_duration
    [-1, Float::INFINITY, "1", nil].each do |duration|
      assert_raises(ArgumentError) { @stick.morph(RED, duration:, cancel: @cancel) }
    end
    refute_sent
  end

  def test_bad_repeats
    BAD_REPEATS.each do |repeats|
      assert_raises(ArgumentError) { @stick.blink(RED, period: 1, repeats:, cancel: @cancel) }
      assert_raises(ArgumentError) { @stick.pulse(RED, duration: 1, repeats:, cancel: @cancel) }
    end
    refute_sent
  end

  def test_bad_colour_sends_nothing
    %i[blink pulse morph].each { |effect| try_effect(effect) }

    refute_sent
  end

  private

  def try_effect(effect)
    timing = effect == :blink ? :period : :duration
    assert_raises(Blinkstick::InvalidColourError) { @stick.public_send(effect, "nope", timing => 1, cancel: @cancel) }
  end

  def refute_sent
    assert_equal 0, handle.attempts
    assert_empty @cancel.waits
  end
end
