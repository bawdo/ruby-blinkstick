# frozen_string_literal: true

require_relative "blinkstick/version"
require_relative "blinkstick/errors"
require_relative "blinkstick/colour"
require_relative "blinkstick/model"
require_relative "blinkstick/report"
require_relative "blinkstick/stick"

# Finds and drives BlinkStick Nano and Square USB LED sticks on macOS and Linux.
#
# Requiring the gem touches no device; the OS backend loads on first use.
#
#   Blinkstick.open do |stick|
#     stick.colour = :cornflowerblue
#   end
module Blinkstick
  # Loaded on first use, so requiring the gem touches no device or backend.
  autoload :Backend, "blinkstick/backend"

  # Lists every attached BlinkStick, including models this gem cannot open
  # (their {Info#model} is {Model::UNKNOWN}).
  #
  # @return [Array<Info>]
  # @raise [Error] when the OS cannot list devices
  def self.list
    Backend.current.list.map { |device| info_for(device) }
  end

  # Opens a BlinkStick: the one with the given serial, or else the first one
  # found. If the first one found is an unknown model this raises, even when
  # a supported stick is also attached; pass a serial from {list} to choose.
  #
  # Without a block the caller must {Stick#close} the stick. With a block,
  # like File.open, the stick is yielded, closed afterwards even if the
  # block raises, and the block's value is returned.
  #
  # @param serial [String, nil] for example "BS072777-3.0"
  # @yieldparam stick [Stick]
  # @return [Stick, Object] the stick, or the block's value
  # @raise [NotFoundError] when no stick (or none with that serial) is attached
  # @raise [UnsupportedModelError] when the stick's model is unknown
  # @raise [BusyError] when another program has seized the stick
  # @raise [PermissionError] when the OS refuses access
  def self.open(serial: nil)
    stick = open_stick(serial)
    return stick unless block_given?

    begin
      yield stick
    ensure
      stick.close
    end
  end

  # Checks the model before opening, so an unknown stick is never opened.
  def self.open_stick(serial)
    backend = Backend.current
    device = find(backend.list, serial)
    info = info_for(device)
    raise UnsupportedModelError, "#{info.serial} is a model this gem does not support" unless info.model.supported?

    Stick.new(backend.open(device), info)
  end

  def self.find(devices, serial)
    return devices.first || raise(NotFoundError, "no BlinkStick attached") if serial.nil?

    devices.find { |device| device.serial == serial } || raise(NotFoundError, "no BlinkStick with serial #{serial}")
  end

  def self.info_for(device)
    Info.from(serial: device.serial, manufacturer: device.manufacturer, product: device.product,
              release: device.release)
  end

  private_class_method :open_stick, :find, :info_for
end
