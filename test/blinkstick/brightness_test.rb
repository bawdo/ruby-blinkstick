# frozen_string_literal: true

require "test_helper"

class BrightnessTest < Minitest::Test
  include FakeBackend::Installer

  Colour = Blinkstick::Colour
  Report = Blinkstick::Report

  ORANGE = Colour.new(red: 255, green: 100, blue: 0)
  HALF = Colour.new(red: 128, green: 50, blue: 0)
  RED = Colour.new(red: 255, green: 0, blue: 0)
  OFF = Colour::OFF

  def teardown
    @stick&.close
    super
  end

  def test_default_limit_and_inverse
    stick = open_stick

    assert_equal 255, stick.brightness_limit
    refute_predicate stick, :inverse?
  end

  def test_limit_scales_every_write_path
    stick = open_stick
    stick.brightness_limit = 128

    stick.colour = [255, 100, 0]
    stick.frame = [ORANGE, ORANGE]
    stick[1] = ORANGE
    stick.off

    assert_equal [Report.frame([HALF, HALF]), Report.frame([HALF, HALF]), Report.led(1, HALF),
                  Report.frame([OFF, OFF])], handle.writes
  end

  def test_reads_return_stored_values
    stick = open_stick
    stick.brightness_limit = 128

    stick.colour = ORANGE

    assert_equal [HALF, HALF], stick.frame
    assert_equal HALF, stick[0]
  end

  def test_limit_validation
    stick = open_stick

    [-1, 256, 1.5, nil, "10"].each do |limit|
      assert_raises(ArgumentError) { stick.brightness_limit = limit }
    end
    assert_equal 255, stick.brightness_limit
  end

  def test_limit_applies_to_later_writes_only
    stick = open_stick
    stick.colour = ORANGE

    stick.brightness_limit = 0

    assert_equal [ORANGE, ORANGE], stick.frame
  end

  def test_inverse_flips_writes_and_reads
    stick = open_stick
    stick.inverse = true

    stick.colour = :red

    assert_predicate stick, :inverse?
    assert_equal [Report.frame([Colour.new(red: 0, green: 255, blue: 255)] * 2)], handle.writes
    assert_equal [RED, RED], stick.frame
  end

  def test_inverse_stores_a_boolean
    stick = open_stick
    stick.inverse = "yes"

    assert_same true, stick.inverse?
    stick.inverse = nil

    assert_same false, stick.inverse?
  end

  def test_inverse_after_limit
    stick = open_stick
    stick.brightness_limit = 0
    stick.inverse = true

    stick.colour = :white
    stick[0] = :white
    stick.off

    white = Colour.new(red: 255, green: 255, blue: 255)

    assert_equal [Report.frame([white, white]), Report.led(0, white), Report.frame([white, white])], handle.writes
    assert_equal [OFF, OFF], stick.frame
  end

  def test_first_led_write_seeds_from_one_read
    stick = open_stick
    handle.leds = [RED] + ([OFF] * 7)

    stick[0] = :green
    stick[1] = :green

    assert_equal({ 6 => 1 }, handle.reads_by_id)
  end

  def test_seed_keeps_other_leds_when_inverse_and_limited
    stick = open_stick
    stick.brightness_limit = 128
    stick.inverse = true
    handle.leds = [Colour.new(red: 255, green: 255, blue: 255)] * 8
    stick[0] = ORANGE

    assert_equal [HALF, OFF], stick.frame
  end

  def test_index_checked_before_colour
    stick = open_stick

    assert_raises(IndexError) { stick[9] = :notacolour }
    assert_equal 0, handle.attempts
  end

  private

  def open_stick
    @backend = install_backend(FakeBackend.new(FakeBackend.nano))
    @stick = Blinkstick.open
  end

  def handle
    @backend.handles.fetch(0)
  end
end
