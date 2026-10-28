# frozen_string_literal: true

require "test_helper"

class EepromTest < Minitest::Test
  include FakeBackend::Installer

  SERIAL = "BS000002-3.1"

  def teardown
    @stick&.close
    super
  end

  def test_write_info_block_pads_and_reads_back
    open_square

    assert_nil @stick.write_info_block(2, "hello")
    assert_equal [Blinkstick::Report.info_block(2, "hello")], handle.writes
    assert_equal "hello".b, @stick.info_block(2)
  end

  def test_write_info_block_validation_sends_nothing
    open_square
    refuse(ArgumentError) { @stick.write_info_block(0, "a") }
    refuse(ArgumentError) { @stick.write_info_block(3, "a") }
    refuse(ArgumentError) { @stick.write_info_block(1, "a" * 33) }
    refuse(TypeError) { @stick.write_info_block(1, nil) }

    assert_equal 0, handle.attempts
  end

  def test_info_block_round_trips_binary
    open_square
    @stick.write_info_block(1, "\xFFa".b)
    block = @stick.info_block(1)

    assert_equal "\xFFa".b, block
    assert_equal Encoding::ASCII_8BIT, block.encoding
  end

  def test_name_round_trip
    open_square
    @stick.name = "desk"

    assert_equal "desk", @stick.name
    @stick.name = ""

    assert_equal "", @stick.name
  end

  def test_name_utf8
    open_square
    @stick.name = "café"

    assert_equal "caf\xC3\xA9".b, handle.writes.last.byteslice(1, 5)
    assert_equal ["café", Encoding::UTF_8], [@stick.name, @stick.name.encoding]
  end

  def test_name_returns_invalid_utf8_unscrubbed
    open_square
    @backend.store(SERIAL, info_blocks: { 1 => "\xFF".b, 2 => "".b })
    name = @stick.name

    assert_equal [0xFF], name.bytes
    refute_predicate name, :valid_encoding?
  end

  def test_bad_names_send_nothing
    open_square
    refuse(TypeError) { @stick.name = :desk }
    [+"a\0b", "\xFF".b, "a" * 33].each { |bad| refuse(ArgumentError) { @stick.name = bad } }

    assert_equal 0, handle.attempts
  end

  def test_name_of_32_bytes_is_accepted
    open_square
    @stick.name = "a" * 32

    assert_equal "a" * 32, @stick.name
  end

  def test_mode_change_writes_once
    open_square(mode: 2)
    @stick.mode = :ws2812_mirror

    assert_equal [[4, 3].pack("C*")], handle.writes
    assert_equal :ws2812_mirror, @stick.mode
  end

  def test_mode_unchanged_skips_write
    open_square(mode: 2)
    @stick.mode = :ws2812

    assert_equal 1, handle.reads_by_id[4]
    assert_empty handle.writes
  end

  def test_mode_accepts_integers
    open_square(mode: 2)
    @stick.mode = 3

    assert_equal :ws2812_mirror, @stick.mode
    @stick.mode = 2

    assert_equal :ws2812, @stick.mode
  end

  def test_refused_modes_send_nothing
    open_square
    [:rgb, :rgb_inverse, 0, 1, 4, "ws2812"].each do |mode|
      error = assert_raises(ArgumentError) { @stick.mode = mode }
      assert_match(/Pro/, error.message)
    end
    assert_equal 0, handle.attempts
  end

  def test_eeprom_writes_refused_by_default_fake
    open_square(eeprom_writes: false)
    assert_raises(FakeBackend::Eeprom::EepromWrite) { @stick.name = "desk" }
  end

  private

  def refuse(error, &)
    assert_raises(error, &)
  end

  def open_square(eeprom_writes: true, **)
    @backend = install_backend(FakeBackend.new(FakeBackend.square(SERIAL), eeprom_writes:, **))
    @stick = Blinkstick.open
  end

  def handle
    @backend.handles.fetch(0)
  end
end
