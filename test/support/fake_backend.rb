# frozen_string_literal: true

# A backend that simulates attached sticks, for tests. It records every
# report written to each handle it opens.
class FakeBackend
  Device = Blinkstick::Backend::Device

  # A simulated open device.
  class Handle
    attr_reader :device, :writes, :stream, :attempts, :leds, :writes_by_id

    def initialize(device, fail_writes:, gone:)
      @device = device
      @failures_left = fail_writes
      @gone = gone
      @writes = []
      @stream = []
      @attempts = 0
      @leds = Array.new(8, Blinkstick::Colour::OFF)
      @writes_by_id = Hash.new(0)
      @closed = false
    end

    # Records the report one byte at a time, yielding the thread between
    # bytes, so two writes that are not serialised by the caller interleave
    # in #stream. There is deliberately no lock here.
    def write_feature(report)
      raise Blinkstick::ClosedError, "fake handle closed" if @closed

      @attempts += 1
      raise Blinkstick::DisconnectedError, "#{device.serial} unplugged" if @gone
      raise Blinkstick::Backend::TransferFailed, "#{device.serial} busy" if (@failures_left -= 1) >= 0

      report.each_byte do |byte|
        @stream << byte
        Thread.pass
      end
      @writes << report
      apply(report)
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end

    private

    # Mirrors the LED state a recorded report leaves on the stick.
    def apply(report)
      id = report.getbyte(0)
      @writes_by_id[id] += 1
      case id
      when Blinkstick::Report::FRAME_ID then @leds = Blinkstick::Report.decode_frame(report, 8)
      when Blinkstick::Report::LED_ID then @leds = @leds.dup.tap { |leds| leds[report.getbyte(2)] = rgb(report) }
      end
    end

    def rgb(report)
      Blinkstick::Colour.new(red: report.getbyte(3), green: report.getbyte(4), blue: report.getbyte(5))
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

  def initialize(*devices, busy: false, permission_denied: false, fail_writes: 0, gone: false)
    @devices = devices
    @busy = busy
    @permission_denied = permission_denied
    @fail_writes = fail_writes
    @gone = gone
    @handles = []
  end

  def list
    @devices
  end

  def open(device)
    raise Blinkstick::BusyError, "#{device.serial} is seized by another program" if @busy
    raise Blinkstick::PermissionError, "#{device.serial}: permission denied" if @permission_denied

    Handle.new(device, fail_writes: @fail_writes, gone: @gone).tap { |handle| @handles << handle }
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
end
