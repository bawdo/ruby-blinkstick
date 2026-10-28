# frozen_string_literal: true

require "test_helper"

class ModelTest < Minitest::Test
  Model = Blinkstick::Model
  Info = Blinkstick::Info

  INFO_CASES = [
    ["BS072777-3.0", 0x0202, Model::NANO, "3.0"],
    ["BS073788-3.1", 0x0201, Model::SQUARE, "3.1"],
    ["BS000001-2.0", 0x0200, Model::UNKNOWN, "2.0"],
    ["BS000002-3.0", 0x0203, Model::UNKNOWN, "3.0"],
    ["BS000003-1.0", 0x0201, Model::UNKNOWN, "1.0"],
    ["garbage", 0x0202, Model::UNKNOWN, ""]
  ].freeze

  def test_info_from
    INFO_CASES.each do |serial, release, model, version|
      info = Info.from(serial: serial, manufacturer: "m", product: "p", release: release)

      assert_equal [model, version], [info.model, info.version], serial
    end
  end

  def test_info_from_keeps_release
    info = Info.from(serial: "BS072777-3.0", manufacturer: "m", product: "p", release: 0x0202)

    assert_equal 0x0202, info.release
  end

  def test_info_copies_strings
    info = Info.from(serial: "BS072777-3.0", manufacturer: "Agile Innovative Ltd",
                     product: "BlinkStick Nano", release: 0x0202)

    assert_equal "BS072777-3.0", info.serial
    assert_equal "Agile Innovative Ltd", info.manufacturer
    assert_equal "BlinkStick Nano", info.product
  end

  def test_model_leds
    assert_equal 2, Model::NANO.leds
    assert_equal 8, Model::SQUARE.leds
    assert_equal 0, Model::UNKNOWN.leds
  end

  def test_model_names
    assert_equal %w[Nano Square unknown], [Model::NANO, Model::SQUARE, Model::UNKNOWN].map(&:name)
  end

  def test_supported
    assert_predicate Model::NANO, :supported?
    assert_predicate Model::SQUARE, :supported?
    refute_predicate Model::UNKNOWN, :supported?
  end

  def test_usb_ids
    assert_equal 0x20A0, Blinkstick::VENDOR_ID
    assert_equal 0x41E5, Blinkstick::PRODUCT_ID
  end
end
