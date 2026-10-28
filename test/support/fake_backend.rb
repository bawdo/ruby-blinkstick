# frozen_string_literal: true

require_relative "fake_backend_handle"

# A backend that simulates attached sticks, for tests. It records every
# report written to each handle it opens, and answers reads from the state
# those writes leave behind.
class FakeBackend
  Device = Blinkstick::Backend::Device
  Report = Blinkstick::Report

  # The backend every test starts with, so a test that forgets to install a
  # FakeBackend fails loudly instead of reaching the real stick attached to
  # the machine running the tests.
  class Refusing
    # Raised by every call. Deliberately outside Blinkstick::Error, so no
    # rescue in the gem or assert_raises in a test can swallow it.
    class NoBackend < StandardError; end

    MESSAGE = "no backend installed for this test: include FakeBackend::Installer " \
              "and call install_backend (the real stick is never used by tests)"

    def list
      raise NoBackend, MESSAGE
    end

    def open(_device)
      raise NoBackend, MESSAGE
    end
  end

  # The one Refusing backend, which test_helper installs and Installer puts back.
  REFUSING = Refusing.new.freeze

  # What a device keeps whatever handles come and go: its EEPROM (mode and
  # info blocks), its LEDs, whether it is plugged in, the handles opened on
  # it, and how many more transfers it refuses after a mode write
  # (busy_left). leds is replaced, never changed in place, so a reference a
  # test holds stays as it was.
  class DeviceState
    DARK = Array.new(8, Blinkstick::Colour::OFF).freeze

    attr_accessor :mode, :info_blocks, :refusal, :leds, :busy_left
    attr_reader :handles, :queued

    def initialize(mode:, info_blocks:)
      @mode = mode
      @info_blocks = info_blocks.dup
      @leds = DARK
      @plugged = true
      @refusal = nil
      @busy_left = 0
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

    # A replugged stick starts dark.
    def replug
      @plugged = true
      @leds = DARK
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

  # @param switches [Hash] failure switches (fail_writes and so on, gone or
  #   busy_after_mode) for the first Handle opened per device; later opens are clean unless
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

  # The device is listed again, with every LED dark.
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
  # puts the Refusing backend back afterwards, never the real one.
  module Installer
    def install_backend(backend)
      Blinkstick::Backend.current = backend
    end

    def teardown
      Blinkstick::Backend.current = REFUSING
      super
    end
  end

  private

  def check_openable(device, state)
    raise state.refusal, "#{device.serial} refused" if state.refusal
    # As hidraw does when the device node is gone (ENOENT or ENODEV).
    raise Blinkstick::NotFoundError, "#{device.serial} is no longer attached" unless state.plugged?
    raise Blinkstick::BusyError, "#{device.serial} is seized by another program" if @busy
    raise Blinkstick::PermissionError, "#{device.serial}: permission denied" if @permission_denied
  end

  def switches_for(state)
    base = state.handles.empty? ? @switches : {}
    base.merge(state.queued.shift || {})
  end
end
