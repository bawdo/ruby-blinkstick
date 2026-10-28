# frozen_string_literal: true

require "test_helper"
require "support/named_sticks"

class NamesListTest < Minitest::Test
  include NamedSticks

  def test_list_with_names
    backend = named_backend("BS000001-3.0" => "desk", "BS000002-3.1" => "shelf")

    named = Blinkstick.list(names: true)

    rows = named.map { |entry| [entry.info.serial, entry.name, entry.busy?] }

    assert_equal [["BS000001-3.0", "desk", false], ["BS000002-3.1", "shelf", false]], rows
    assert_equal [true, true], closed_states(backend)
  end

  def test_list_with_names_returns_named_infos
    named_backend("BS000001-3.0" => "desk")

    assert_instance_of Blinkstick::NamedInfo, Blinkstick.list(names: true).first
  end

  def test_list_with_names_marks_busy
    backend = named_backend("BS000001-3.0" => "desk", "BS000002-3.1" => "shelf")
    backend.refuse("BS000001-3.0", Blinkstick::BusyError)

    named = Blinkstick.list(names: true)

    rows = named.map { |entry| [entry.name, entry.busy] }

    assert_equal [["", true], ["shelf", false]], rows
  end

  def test_list_with_names_reads_unknown_models
    backend = install_backend(FakeBackend.new(FakeBackend.unknown))
    backend.store("BS000003-2.0", info_blocks: { 1 => "odd".b, 2 => "".b })

    named = Blinkstick.list(names: true)

    rows = named.map { |entry| [entry.name, entry.info.model] }

    assert_equal [["odd", Blinkstick::Model::UNKNOWN]], rows
    assert_equal [true], closed_states(backend)
  end

  def test_list_with_names_closes_on_read_failure
    backend = named_backend("BS000001-3.0" => "desk")
    backend.next_open("BS000001-3.0", fail_reads: 99)

    assert_equal [true], Blinkstick.list(names: true).map(&:busy?)
    assert_equal [true], closed_states(backend)
  end

  def test_plain_list_opens_nothing
    backend = named_backend("BS000001-3.0" => "desk")

    assert_equal 1, Blinkstick.list.size
    assert_empty backend.handles
  end
end
