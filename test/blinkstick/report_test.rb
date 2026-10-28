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

  def test_led_is_rgb_order
    report = Report.led(3, Colour.new(red: 1, green: 2, blue: 3))

    assert_equal [5, 0, 3, 1, 2, 3], report.bytes
    assert_equal Encoding::ASCII_8BIT, report.encoding
    assert_predicate report, :frozen?
  end

  def test_led_rejects_bad_index
    [-1, 256, 1.0].each do |index|
      assert_raises(ArgumentError) { Report.led(index, Colour::OFF) }
    end
  end

  def test_decode_frame_round_trip
    colours = (1..8).map { |i| Colour.new(red: i, green: i + 10, blue: i + 20) }
    bytes = Report.frame(colours).bytes

    decoded = Report.decode_frame(bytes, 8)

    assert_equal colours, decoded
    assert_predicate decoded, :frozen?
    assert_equal colours.first(2), Report.decode_frame(bytes, 2)
  end

  def test_decode_mode
    modes = [0, 1, 2, 3, 9].map { |byte| Report.decode_mode([4, byte]) }

    assert_equal [:rgb, :rgb_inverse, :ws2812, :ws2812_mirror, 9], modes
  end

  def test_info_block_ids
    assert_equal 2, Report.info_block_id(1)
    assert_equal 3, Report.info_block_id(2)
    [0, 3, "1"].each do |n|
      assert_raises(ArgumentError) { Report.info_block_id(n) }
    end
  end

  def test_decode_info_block
    text = Report.decode_info_block([2] + "hi".bytes + ([0] * 30))

    assert_equal "hi", text
    assert_equal Encoding::ASCII_8BIT, text.encoding
    assert_predicate text, :frozen?
  end

  def test_decode_info_block_empty_and_embedded_nul
    assert_equal "", Report.decode_info_block([2] + ([0] * 32))
    assert_equal "a\0b", Report.decode_info_block([2, 0x61, 0, 0x62] + ([0] * 29))
  end

  def test_info_block_pads
    report = Report.info_block(2, "ab".b)

    assert_equal [3, 97, 98] + ([0] * 30), report.bytes
    assert_predicate report, :frozen?
    assert_equal Encoding::BINARY, report.encoding
  end

  def test_info_block_accepts_the_maximum_refuses_one_more
    assert_equal 33, Report.info_block(1, "a".b * 32).bytesize
    assert_raises(ArgumentError) { Report.info_block(1, "a".b * 33) }
  end

  def test_info_block_writes_utf8_bytes
    assert_equal [2, 0xC3, 0xA9] + ([0] * 30), Report.info_block(1, "é").bytes
  end

  def test_mode_report
    report = Report.mode(3)

    assert_equal [4, 3], report.bytes
    assert_predicate report, :frozen?
    assert_equal Encoding::BINARY, report.encoding
  end

  def test_mode_refuses_bad_bytes
    [-1, 256, "1", nil, 1.0].each { |byte| assert_raises(ArgumentError) { Report.mode(byte) } }
  end

  def test_decode_frame_refuses_short_input
    assert_raises(ArgumentError) { Report.decode_frame([0] * 25, 8) }
    assert_raises(ArgumentError) { Report.decode_frame("\0".b * 25, 8) }
  end

  def test_decode_mode_refuses_short_input
    assert_raises(ArgumentError) { Report.decode_mode([4]) }
  end

  def test_decode_info_block_refuses_short_input
    assert_raises(ArgumentError) { Report.decode_info_block([0] * 32) }
  end
end
