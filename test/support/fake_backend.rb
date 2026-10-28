# frozen_string_literal: true

require_relative "fake_backend_handle"

# A backend that simulates attached sticks, for tests. It records every
# report written to each handle it opens, and answers reads from the state
# those writes leave behind.
class FakeBackend
  Device = Blinkstick::Backend::Device
  Report = Blinkstick::Report

  # What a device keeps whatever handles come and go: its EEPROM (mode and
  # info blocks), whether it is plugged in, and the handles opened on it.
  class DeviceState
    attr_accessor :mode, :info_blocks, :refusal
    attr_reader :handles, :queued

    def initialize(mode:, info_blocks:)
      @mode = mode
      @info_blocks = info_blocks.dup
      @plugged = true
      @refusal = nil
      @handles = []
      @queued = []
    end

    def plugged?
      @plugged
    end

    def unplug
      @plugged = false
      @handles.each(&:unplug)
    end

    def replug
      @plugged = true
    end
  end

  # @return [Device] a Nano with the given serial
  def self.nano(serial = "BS000001-3.0")
    device(serial, 0x0202)
  end

  # @return [Device] a Square with the given serial
  def self.square(serial = "BS000002-3.1")
    device(serial, 0x0201)
  end

  # @return [Device] a stick of a model the gem does not know
  def self.unknown(serial = "BS000003-2.0")
    device(serial, 0x0200)
  end

  def self.device(serial, release)
    Device.new(id: "fake:#{serial}", serial: serial, manufacturer: "Agile Innovative Ltd",
               product: "BlinkStick", release: release)
  end

  attr_reader :handles

  # @param switches [Hash] failure switches (fail_writes and so on, or gone)
  #   for the first Handle opened per device; later opens are clean unless
  #   #next_open queued some
  # @param eeprom_writes [Boolean] let handles accept reports 2, 3 and 4
  # @param mode [Integer] every device's starting mode byte
  # @param info_blocks [Hash] every device's starting info blocks
  def initialize(*devices, busy: false, permission_denied: false, **switches)
    @devices = devices
    @busy = busy
    @permission_denied = permission_denied
    @eeprom_writes = switches.delete(:eeprom_writes) || false
    eeprom = { mode: switches.delete(:mode) || 2,
               info_blocks: switches.delete(:info_blocks) || { 1 => "".b, 2 => "".b } }
    @switches = switches
    @handles = []
    @states = devices.to_h { |device| [device.serial, DeviceState.new(**eeprom)] }
  end

  def list
    @devices.select { |device| @states.fetch(device.serial).plugged? }
  end

  def open(device)
    state = @states.fetch(device.serial)
    check_openable(device, state)

    Handle.new(device, state, eeprom_writes: @eeprom_writes, **switches_for(state)).tap do |handle|
      state.handles << handle
      @handles << handle
    end
  end

  # Sets one device's stored EEPROM state; nil leaves a part as it is.
  def store(serial, mode: nil, info_blocks: nil)
    state = @states.fetch(serial)
    state.mode = mode unless mode.nil?
    state.info_blocks = info_blocks.dup unless info_blocks.nil?
  end

  # Queues switches for the next open of this serial only.
  def next_open(serial, **switches)
    @states.fetch(serial).queued << switches
  end

  # The device leaves #list and its open handles raise DisconnectedError.
  def unplug(serial)
    @states.fetch(serial).unplug
  end

  # The device is listed again; handles opened from now on start dark.
  def replug(serial)
    @states.fetch(serial).replug
  end

  # Makes opens of this serial raise error_class; nil clears it.
  def refuse(serial, error_class)
    @states.fetch(serial).refusal = error_class
  end

  # @return [Array<Handle>] the handles opened on this serial, in order
  def handles_for(serial)
    @states.fetch(serial).handles.dup
  end

  # Installs a FakeBackend as Blinkstick::Backend.current for one test and
  # puts the previous backend back afterwards.
  module Installer
    def install_backend(backend)
      @previous_backend = Blinkstick::Backend.instance_variable_get(:@current) unless defined?(@previous_backend)
      Blinkstick::Backend.current = backend
    end

    def teardown
      Blinkstick::Backend.current = @previous_backend if defined?(@previous_backend)
      super
    end
  end

  private

  def check_openable(device, state)
    raise state.refusal, "#{device.serial} refused" if state.refusal
    raise Blinkstick::DisconnectedError, "#{device.serial} is unplugged" unless state.plugged?
    raise Blinkstick::BusyError, "#{device.serial} is seized by another program" if @busy
    raise Blinkstick::PermissionError, "#{device.serial}: permission denied" if @permission_denied
  end

  def switches_for(state)
    base = state.handles.empty? ? @switches : {}
    base.merge(state.queued.shift || {})
  end
end
