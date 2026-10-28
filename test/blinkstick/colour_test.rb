# frozen_string_literal: true

require "test_helper"

class ColourTest < Minitest::Test
  Colour = Blinkstick::Colour
  ORANGE = Colour.new(red: 255, green: 136, blue: 0)

  def test_parses_hex_forms
    ["#ff8800", "ff8800", "#F80", "f80", "  #FF8800  "].each do |input|
      assert_equal ORANGE, Colour.parse(input), input.inspect
    end
  end

  def test_parses_decimal_triples
    ["255,136,0", " 255 , 136 , 0 "].each do |input|
      assert_equal ORANGE, Colour.parse(input), input.inspect
    end
  end

  def test_parses_names_any_case
    expected = Colour.new(red: 100, green: 149, blue: 237)

    ["cornflowerblue", "CornflowerBlue", :cornflowerblue, :CornflowerBlue].each do |input|
      assert_equal expected, Colour.parse(input), input.inspect
    end
  end

  def test_parses_arrays_and_colours
    assert_equal ORANGE, Colour.parse([255, 136, 0])
    assert_same ORANGE, Colour.parse(ORANGE)
  end

  def test_rejects_bad_input
    ["", "#ff88", "#gg0000", "256,0,0", "1,2", "1,2,3,4", "+1,2,3", "-1,2,3", "notacolour",
     :notacolour, [255, 0], [256, 0, 0], [1.0, 2, 3], nil, 42].each do |input|
      assert_raises(Blinkstick::InvalidColourError, input.inspect) { Colour.parse(input) }
    end
    assert_operator Blinkstick::InvalidColourError, :<=, ArgumentError
  end

  # Bytes that are not valid in the String's encoding must not escape as a
  # bare ArgumentError or Encoding::CompatibilityError.
  def test_rejects_invalid_encoding
    ["\xFFred", "ff\xFF00", "#ff\xFF00", "\xFF,0,0", "red".b + "\xFF".b].each do |input|
      assert_raises(Blinkstick::InvalidColourError, input.inspect) { Colour.parse(input) }
    end
  end

  def test_error_message_includes_input
    error = assert_raises(Blinkstick::InvalidColourError) { Colour.parse("notacolour") }
    assert_equal 'invalid colour "notacolour"', error.message
  end

  def test_new_validates_channels
    assert_raises(Blinkstick::InvalidColourError) { Colour.new(red: 300, green: 0, blue: 0) }
  end

  def test_hex_is_lower_case
    assert_equal "#ff8800", ORANGE.hex
    assert_equal "#ff8800", ORANGE.to_s
  end

  def test_names
    names = Colour.names

    assert_equal 148, names.size
    assert_equal names.sort, names
    assert_predicate names, :frozen?
  end

  def test_names_membership
    assert_includes Colour.names, "rebeccapurple"
    refute_includes Colour.names, "transparent"
  end

  def test_every_name_parses
    Colour.names.each { |name| assert_kind_of Colour, Colour.parse(name), name }
  end

  def test_off
    assert_equal Colour.new(red: 0, green: 0, blue: 0), Colour::OFF
  end

  def test_colours_are_immutable_values
    other = Colour.new(red: 255, green: 136, blue: 0)

    assert_predicate ORANGE, :frozen?
    assert_equal ORANGE, other
    assert_equal ORANGE.hash, other.hash
  end

  def test_error_hierarchy
    %i[NotFoundError BusyError PermissionError UnsupportedModelError ClosedError DisconnectedError].each do |name|
      assert_operator Blinkstick.const_get(name), :<, Blinkstick::Error
    end
    assert_operator Blinkstick::Error, :<, StandardError
  end
end
