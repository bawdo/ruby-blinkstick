# frozen_string_literal: true

require "test_helper"
require "support/named_sticks"

class NamesTest < Minitest::Test
  include NamedSticks

  def test_open_by_name
    backend = named_backend("BS000001-3.0" => "desk", "BS000002-3.1" => "shelf")

    stick = Blinkstick.open(name: "shelf")

    assert_equal "BS000002-3.1", stick.info.serial
    assert_equal [true, false], closed_states(backend)
  ensure
    stick&.close
  end

  def test_open_by_name_block_form
    backend = named_backend("BS000001-3.0" => "desk", "BS000002-3.1" => "shelf")

    result = Blinkstick.open(name: "desk") { |stick| stick.info.serial }

    assert_equal "BS000001-3.0", result
    assert_equal [true, true], closed_states(backend)
  end

  def test_name_not_found_lists_skipped
    backend = named_backend("BS000001-3.0" => "desk", "BS000002-3.1" => "shelf")
    backend.refuse("BS000002-3.1", Blinkstick::BusyError)

    error = assert_raises(Blinkstick::NotFoundError) { Blinkstick.open(name: "lamp") }

    assert_match(/lamp.*"BS000002-3\.1" \(BusyError: .*refused/, error.message)
    refute_includes error.message, "BS000001-3.0"
  end

  def test_busy_stick_does_not_hide_a_match
    backend = named_backend("BS000001-3.0" => "desk", "BS000002-3.1" => "shelf")
    backend.refuse("BS000001-3.0", Blinkstick::BusyError)

    Blinkstick.open(name: "shelf") { |stick| assert_equal "BS000002-3.1", stick.info.serial }
  end

  def test_duplicate_names_close_everything
    backend = named_backend("BS000001-3.0" => "desk", "BS000002-3.1" => "desk", "BS000004-3.0" => "other")

    error = assert_raises(Blinkstick::DuplicateNameError) { Blinkstick.open(name: "desk") }

    assert_includes error.message, '"BS000001-3.0", "BS000002-3.1"'
    assert_equal [true, true, true], closed_states(backend)
  end

  def test_unknown_model_match_refused
    backend = install_backend(FakeBackend.new(FakeBackend.unknown, FakeBackend.nano))
    backend.store("BS000003-2.0", info_blocks: { 1 => "odd".b, 2 => "".b })

    error = assert_raises(Blinkstick::UnsupportedModelError) { Blinkstick.open(name: "odd") }

    assert_includes error.message, "BS000003-2.0"
    assert_equal [true, true], closed_states(backend)
  end

  def test_name_compared_byte_for_byte
    named_backend("BS000001-3.0" => "Desk")

    assert_raises(Blinkstick::NotFoundError) { Blinkstick.open(name: "desk") }
  end

  def test_exception_while_reading_a_name_leaves_nothing_open
    backend = named_backend("BS000001-3.0" => "desk", "BS000002-3.1" => "shelf")
    backend.next_open("BS000002-3.1", fail_reads: 99)

    assert_raises(Blinkstick::NotFoundError) { Blinkstick.open(name: "shelf") }
    assert_equal [true, true], closed_states(backend)
  end

  def test_exception_part_way_through_closes_handles_already_kept
    backend = named_backend("BS000001-3.0" => "desk", "BS000002-3.1" => "shelf", "BS000004-3.0" => "other")
    backend.refuse("BS000004-3.0", RuntimeError)

    assert_raises(RuntimeError) { Blinkstick.open(name: "shelf") }
    assert_equal [true, true], closed_states(backend)
  end

  def test_name_and_serial_together_refused
    backend = named_backend("BS000001-3.0" => "desk")

    assert_raises(ArgumentError) { Blinkstick.open(serial: "BS000001-3.0", name: "desk") }
    assert_empty backend.handles
  end

  def test_empty_and_non_string_names_refused
    backend = named_backend("BS000001-3.0" => "desk")

    assert_raises(ArgumentError) { Blinkstick.open(name: "") }
    [:desk, 7, ["desk"]].each { |bad| assert_raises(TypeError) { Blinkstick.open(name: bad) } }
    assert_empty backend.handles
  end
end
