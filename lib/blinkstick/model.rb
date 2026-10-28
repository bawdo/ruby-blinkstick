# frozen_string_literal: true

module Blinkstick
  # USB vendor ID shared by every BlinkStick model.
  VENDOR_ID = 0x20A0

  # USB product ID shared by every BlinkStick model.
  PRODUCT_ID = 0x41E5

  # A BlinkStick product, described by its name and addressable LED count.
  Model = Data.define(:name, :leds) do
    # @return [Boolean] false only for {UNKNOWN}, which can be listed but not opened
    def supported?
      self != Model::UNKNOWN
    end
  end

  Model::NANO = Model.new(name: "Nano", leds: 2)
  Model::SQUARE = Model.new(name: "Square", leds: 8)
  Model::UNKNOWN = Model.new(name: "unknown", leds: 0)

  # Maps [serial major version, USB bcdDevice] to a {Model}. A Square
  # (BS073788-3.1) reports 0x0201, so that value is not a Strip here.
  MODELS = {
    ["3", 0x0202] => Model::NANO,
    ["3", 0x0201] => Model::SQUARE
  }.freeze
  private_constant :MODELS

  # Identifies an attached BlinkStick. It holds no OS path or handle.
  Info = Data.define(:serial, :version, :manufacturer, :product, :model) do
    # @param serial [String] for example "BS072777-3.0"
    # @param manufacturer [String]
    # @param product [String]
    # @param release [Integer] the USB bcdDevice value
    # @return [Info]
    def self.from(serial:, manufacturer:, product:, release:)
      _, _, version = serial.partition("-")
      major, = version.split(".", 2)
      new(serial: serial, version: version, manufacturer: manufacturer, product: product,
          model: MODELS.fetch([major, release], Model::UNKNOWN))
    end
  end
end
