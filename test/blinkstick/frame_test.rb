# frozen_string_literal: true

require "test_helper"

class FrameTest < Minitest::Test
  include FakeBackend::Installer

  Colour = Blinkstick::Colour
  Report = Blinkstick::Report

  RED = Colour.new(red: 255, green: 0, blue: 0)
  GREEN = Colour.new(red: 0, green: 255, blue: 0)

  def teardown
    @stick&.close
    super
  end

  def test_sends_one_report6
    stick = open_stick(FakeBackend.nano)

    stick.frame = [:red, "#00ff00"]

    assert_equal [Report.frame([RED, GREEN])], handle.writes
  end

  def test_wrong_length
    stick = open_stick(FakeBackend.nano)

    messages = [[:red], [:red] * 3].map { |colours| assert_raises(ArgumentError) { stick.frame = colours }.message }

    assert(messages.all? { |m| m.include?("2") && m.include?("Nano") })
    assert_equal 0, handle.attempts
  end

  def test_not_array
    stick = open_stick(FakeBackend.nano)

    ["red", nil, { a: 1 }, %i[red red].each].each do |input|
      assert_raises(TypeError) { stick.frame = input }
    end
    assert_equal 0, handle.attempts
  end

  def test_with_one_bad_colour_sends_nothing
    stick = open_stick(FakeBackend.nano)

    assert_raises(Blinkstick::InvalidColourError) { stick.frame = %i[red notacolour] }
    assert_equal 0, handle.attempts
  end

  private

  def open_stick(device)
    @backend = install_backend(FakeBackend.new(device))
    @stick = Blinkstick.open
  end

  def handle
    @backend.handles.fetch(0)
  end
end
