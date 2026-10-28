# frozen_string_literal: true

require "test_helper"

class ReportTest < Minitest::Test
  Colour = Blinkstick::Colour
  Report = Blinkstick::Report

  def test_frame_is_grb_with_zero_padding
    frame = Report.frame([Colour.new(red: 1, green: 2, blue: 3)] * 2)

    assert_equal [6, 0, 2, 1, 3, 2, 1, 3] + ([0] * 18), frame.bytes
  end

  def test_frame_square
    colours = (1..8).map { |i| Colour.new(red: i, green: i + 10, blue: i + 20) }
    expected = [6, 0] + colours.flat_map { |c| [c.green, c.red, c.blue] }

    assert_equal expected, Report.frame(colours).bytes
  end

  def test_frame_rejects_more_than_eight
    assert_raises(ArgumentError) { Report.frame([Colour::OFF] * 9) }
  end

  def test_frame_is_binary
    frame = Report.frame([])

    assert_equal Encoding::ASCII_8BIT, frame.encoding
    assert_equal 26, frame.bytesize
    assert_predicate frame, :frozen?
  end
end
