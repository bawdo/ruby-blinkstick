# frozen_string_literal: true

require "test_helper"

class ColourRandomTest < Minitest::Test
  Colour = Blinkstick::Colour

  def test_random_any_uses_the_generator
    assert_equal Colour.random(random: Random.new(1)), Colour.random(random: Random.new(1))

    generator = Random.new(3)

    200.times { assert_instance_of Colour, Colour.random(random: generator) }
  end

  def test_random_vivid_is_saturated
    generator = Random.new(2)

    500.times do
      colour = Colour.random(vivid: true, random: generator)
      channels = [colour.red, colour.green, colour.blue]

      assert_includes channels, 255, colour.inspect
      assert_includes channels, 0, colour.inspect
    end
  end

  FixedRandom = Struct.new(:value) do
    def rand(limit)
      raise ArgumentError, "unexpected #{limit}" unless limit == 1530

      value
    end
  end

  # Hands out 10, 20, 30 in turn and records every limit asked for.
  class CountingRandom
    attr_reader :limits

    def initialize
      @limits = []
    end

    def rand(limit)
      @limits << limit
      @limits.size * 10
    end
  end

  def test_random_any_draws_one_byte_per_channel_in_order
    generator = CountingRandom.new
    colour = Colour.random(random: generator)

    assert_equal [256, 256, 256], generator.limits
    assert_equal [10, 20, 30], [colour.red, colour.green, colour.blue]
  end

  def test_hue_segments
    {
      0 => [255, 0, 0], 255 => [255, 255, 0], 510 => [0, 255, 0], 765 => [0, 255, 255],
      1020 => [0, 0, 255], 1275 => [255, 0, 255], 1529 => [255, 0, 1]
    }.each do |step, channels|
      colour = Colour.random(vivid: true, random: FixedRandom.new(step))

      assert_equal channels, [colour.red, colour.green, colour.blue], "step #{step}"
    end
  end
end
