# frozen_string_literal: true

require_relative "blinkstick/version"
require_relative "blinkstick/errors"
require_relative "blinkstick/colour"
require_relative "blinkstick/model"
require_relative "blinkstick/report"
require_relative "blinkstick/stick/eeprom"
require_relative "blinkstick/stick/effects"
require_relative "blinkstick/stick/handover"
require_relative "blinkstick/stick/lighting"
require_relative "blinkstick/stick/reconnect"
require_relative "blinkstick/stick"
require_relative "blinkstick/names"
require_relative "blinkstick/cancellation"

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
  # With +names: true+ each stick is opened briefly to read its name and then
  # closed, so a stick another program holds shows as busy with an empty name.
  # Unknown models are opened too.
  #
  # @param names [Boolean] read each stick's name
  # @return [Array<Info>, Array<NamedInfo>] NamedInfo when +names+ is true
  # @raise [Error] when the OS cannot list devices
  def self.list(names: false)
    return list_named if names

    Backend.current.list.map { |device| info_for(device) }
  end

  # Opens a BlinkStick: the one with the given serial, the one with the given
  # name, or else the first one found. If the first one found is an unknown
  # model this raises, even when a supported stick is also attached; pass a
  # serial from {list} to choose.
  #
  # Without a block the caller must {Stick#close} the stick. With a block,
  # like File.open, the stick is yielded, closed afterwards even if the
  # block raises, and the block's value is returned.
  #
  # By name, every stick is opened in turn and its name read (byte for byte);
  # sticks that cannot be opened or read are skipped, and the others closed.
  #
  # @param serial [String, nil] for example "BS072777-3.0"
  # @param name [String, nil] a name stored on the stick, see {Stick#name=}
  # @yieldparam stick [Stick]
  # @return [Stick, Object] the stick, or the block's value
  # @raise [ArgumentError] when both +serial+ and +name+ are given, or +name+ is empty
  # @raise [TypeError] when +name+ is not a String
  # @raise [NotFoundError] when no stick (or none with that serial or name) is attached;
  #   for a name the message says why each skipped stick was skipped
  # @raise [DuplicateNameError] when more than one stick has that name
  # @raise [UnsupportedModelError] when the stick's model is unknown
  # @raise [BusyError] when another program has seized the stick
  # @raise [PermissionError] when the OS refuses access
  def self.open(serial: nil, name: nil)
    check_selectors(serial, name)
    stick = name.nil? ? open_stick(serial) : open_named(name)
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
    build_stick(backend, find(backend.list, serial))
  end

  # The one place a Stick for a user is built, however it was found. Checks
  # the model first, then takes the handle from the block (when the caller
  # already holds one open) or opens the device, and gives the Stick a way
  # to find the device again after an unplug.
  def self.build_stick(backend, device)
    info = supported_info(device)
    handle = block_given? ? yield : backend.open(device)
    Stick.new(handle, info, reopen: reopener(device.serial))
  end

  # A callable that relists through the current backend and opens the one
  # stick with this serial, after the same model check {Blinkstick.open} makes. An
  # empty serial, or one more than one stick shares, could reopen the wrong
  # stick, so those never reconnect.
  def self.reopener(serial)
    return -> { raise DisconnectedError, "this stick has no serial, so it cannot be found again" } if serial.empty?

    lambda do
      backend = Backend.current
      device = only_device(backend.list, serial)
      supported_info(device)
      backend.open(device)
    end
  end

  # The one device with this serial, for {reopener}.
  def self.only_device(devices, serial)
    matches = devices.select { |device| device.serial == serial }
    raise NotFoundError, "no BlinkStick with serial #{serial.inspect}" if matches.empty?
    raise DisconnectedError, "serial #{serial.inspect} is ambiguous: #{matches.size} sticks have it" if matches.size > 1

    matches.first
  end

  # The model check, made before anything is opened.
  def self.supported_info(device)
    info_for(device).tap do |info|
      raise UnsupportedModelError, "#{info.serial} is a model this gem does not support" unless info.model.supported?
    end
  end

  def self.find(devices, serial)
    return devices.first || raise(NotFoundError, "no BlinkStick attached") if serial.nil?

    devices.find { |device| device.serial == serial } ||
      raise(NotFoundError, "no BlinkStick with serial #{serial.inspect}")
  end

  def self.info_for(device)
    Info.from(serial: device.serial, manufacturer: device.manufacturer, product: device.product,
              release: device.release)
  end

  private_class_method :open_stick, :build_stick, :reopener, :only_device, :supported_info, :find, :info_for
end
