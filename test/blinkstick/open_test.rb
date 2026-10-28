# frozen_string_literal: true

require "test_helper"

class OpenTest < Minitest::Test
  include FakeBackend::Installer

  Model = Blinkstick::Model

  def test_list_returns_info_for_every_device
    install_backend(FakeBackend.new(FakeBackend.nano, FakeBackend.square, FakeBackend.unknown))

    infos = Blinkstick.list

    assert_equal %w[BS000001-3.0 BS000002-3.1 BS000003-2.0], infos.map(&:serial)
    assert_equal [Model::NANO, Model::SQUARE, Model::UNKNOWN], infos.map(&:model)
    assert_equal ["Agile Innovative Ltd"], infos.map(&:manufacturer).uniq
  end

  def test_list_and_open_carry_release
    install_backend(FakeBackend.new(FakeBackend.nano))

    assert_equal [0x0202], Blinkstick.list.map(&:release)
    Blinkstick.open { |stick| assert_equal 0x0202, stick.info.release }
  end

  def test_open_first
    backend = install_backend(FakeBackend.new(FakeBackend.nano, FakeBackend.square))

    stick = Blinkstick.open

    assert_equal "BS000001-3.0", stick.info.serial
    assert_equal [FakeBackend.nano], backend.handles.map(&:device)
  ensure
    stick&.close
  end

  def test_open_by_serial
    backend = install_backend(FakeBackend.new(FakeBackend.nano, FakeBackend.square))

    stick = Blinkstick.open(serial: "BS000002-3.1")

    assert_equal Model::SQUARE, stick.info.model
    assert_equal [FakeBackend.square], backend.handles.map(&:device)
  ensure
    stick&.close
  end

  def test_open_serial_not_found
    install_backend(FakeBackend.new(FakeBackend.nano))

    error = assert_raises(Blinkstick::NotFoundError) { Blinkstick.open(serial: "BS999999-3.0") }

    assert_includes error.message, "BS999999-3.0"
  end

  def test_open_none_attached
    install_backend(FakeBackend.new)

    assert_raises(Blinkstick::NotFoundError) { Blinkstick.open }
  end

  def test_open_unsupported_model_never_opens_it
    backend = install_backend(FakeBackend.new(FakeBackend.unknown, FakeBackend.nano))

    [{}, { serial: "BS000003-2.0" }].each do |args|
      error = assert_raises(Blinkstick::UnsupportedModelError) { Blinkstick.open(**args) }

      assert_includes error.message, "BS000003-2.0"
    end
    assert_empty backend.handles
  end

  def test_busy
    install_backend(FakeBackend.new(FakeBackend.nano, busy: true))

    assert_raises(Blinkstick::BusyError) { Blinkstick.open }
  end

  def test_permission
    install_backend(FakeBackend.new(FakeBackend.nano, permission_denied: true))

    assert_raises(Blinkstick::PermissionError) { Blinkstick.open }
  end

  def test_two_sticks_are_independent
    backend = install_backend(FakeBackend.new(FakeBackend.nano, FakeBackend.square))
    nano, square = %w[BS000001-3.0 BS000002-3.1].map { |serial| Blinkstick.open(serial: serial) }

    nano.colour = :red
    square.colour = :blue
    nano.close
    square.off

    assert_equal [[true, [frame(:red, 2)]], [false, [frame(:blue, 8), frame(:black, 8)]]], states(backend)
  end

  def test_block_form_closes_and_returns_value
    backend = install_backend(FakeBackend.new(FakeBackend.nano))
    seen = nil

    result = Blinkstick.open do |stick|
      seen = stick
      stick.colour = :green
      :done
    end

    assert_equal :done, result
    assert_predicate seen, :closed?
    assert_predicate backend.handles.first, :closed?
  end

  def test_block_raising_closes_stick_and_propagates
    backend = install_backend(FakeBackend.new(FakeBackend.nano))
    boom = RuntimeError.new("boom")

    raised = assert_raises(RuntimeError) do
      Blinkstick.open do |stick|
        @seen = stick
        raise boom
      end
    end

    assert_same boom, raised
    assert_equal [true, true], [@seen.closed?, backend.handles.first.closed?]
  end

  private

  # [closed?, writes] for every handle the backend opened, in order.
  def states(backend)
    backend.handles.map { |handle| [handle.closed?, handle.writes] }
  end

  def frame(colour, leds)
    Blinkstick::Report.frame([Blinkstick::Colour.parse(colour)] * leds)
  end
end
