# frozen_string_literal: true

# Finding sticks by the name stored on them.
module Blinkstick
  # A stick's identity and the name stored on it, from {Blinkstick.list}
  # with +names: true+. A stick that could not be opened or read is +busy+
  # with an empty +name+.
  #
  # @!attribute [r] info
  #   @return [Info]
  # @!attribute [r] name
  #   @return [String] "" when the stick has no name or could not be read
  # @!attribute [r] busy
  #   @return [Boolean]
  NamedInfo = Data.define(:info, :name, :busy) do
    # @return [Boolean] true when the stick could not be opened or read
    def busy?
      busy
    end
  end

  # One stick seen while looking for a name: its device, name and open Stick,
  # or the Error that stopped it being read.
  Reading = Data.define(:device, :name, :error, :stick)
  private_constant :Reading

  class << self
    private

    def check_selectors(serial, name)
      raise ArgumentError, "pass serial: or name:, not both" unless serial.nil? || name.nil?
      return if name.nil?
      raise TypeError, "name must be a String, got #{name.class}" unless name.is_a?(String)
      raise ArgumentError, "name must not be empty" if name.empty?
    end

    # Opens without the model check and without reconnecting: for reading a
    # name, never handed to a caller as it is.
    def open_any(backend, device)
      info = info_for(device)
      Stick.new(backend.open(device), info)
    end

    # Opens, reads the name and closes again, whatever happens in between.
    def read_name(backend, device)
      stick = open_any(backend, device)
      begin
        stick.name
      ensure
        stick.close
      end
    end

    def list_named
      backend = Backend.current
      backend.list.map do |device|
        NamedInfo.new(info: info_for(device), name: read_name(backend, device), busy: false)
      rescue Error
        NamedInfo.new(info: info_for(device), name: "", busy: true)
      end
    end

    # Keeps every readable stick open until the match is known, then hands
    # the match's handle to a new Stick and closes the rest.
    def open_named(name)
      backend = Backend.current
      readings = []
      begin
        backend.list.each { |device| readings << try_keep(backend, device) }
        match = single_match(name, readings)
        build_stick(backend, match.device) { match.stick.detach }
      ensure
        readings.each { |reading| reading.stick&.close }
      end
    end

    def single_match(name, readings)
      matches = readings.select { |reading| reading.name&.b == name.b }
      raise name_error(name, matches.map(&:device), readings) unless matches.size == 1

      matches.first
    end

    # @return [Reading] with the stick still open, or with the Error when it
    #   could not be opened or read
    def try_keep(backend, device)
      stick = open_any(backend, device)
      begin
        Reading.new(device, stick.name, nil, stick).tap { stick = nil }
      ensure
        stick&.close
      end
    rescue Error => e
      Reading.new(device, nil, e, nil)
    end

    def name_error(name, matches, readings)
      matches.empty? ? not_found_name(name, readings) : duplicate_name(name, matches)
    end

    def duplicate_name(name, matches)
      DuplicateNameError.new("#{matches.size} sticks are named #{name.inspect}: " \
                             "#{matches.map { |device| device.serial.inspect }.join(', ')}")
    end

    def not_found_name(name, readings)
      skipped = readings.filter_map do |reading|
        error = reading.error
        "#{reading.device.serial.inspect} (#{error.class.name.split('::').last}: #{error.message})" if error
      end
      message = "no BlinkStick named #{name.inspect}"
      message += "; skipped #{skipped.join(', ')}" unless skipped.empty?
      NotFoundError.new(message)
    end
  end
end
