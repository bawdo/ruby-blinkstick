# frozen_string_literal: true

# A backend that simulates attached sticks, for tests. It records every
# report written to each handle it opens, and answers reads from the state
# those writes leave behind.
class FakeBackend
  Device = Blinkstick::Backend::Device
  Report = Blinkstick::Report

  # A simulated open device.
  #
  # Switches, all optional: fail_writes, fail_reads, short_reads and
  # wrong_id_reads are how many attempts in a row go wrong before the fake
  # behaves (raising TransferFailed, returning one byte too few, or
  # returning the wrong first byte); gone makes every transfer raise
  # DisconnectedError; mode is the mode byte; info_blocks maps 1 and 2 to
  # the stored text.
  class Handle
    FAILURES = %i[fail_writes fail_reads short_reads wrong_id_reads].freeze

    # Reports kept in EEPROM: info blocks 1 and 2, and the mode.
    EEPROM_IDS = [2, 3, Report::MODE_ID].freeze

    # Raised for a write the gem must never send. Deliberately outside
    # Blinkstick::Error, so no rescue in the gem or assert_raises in a test
    # can swallow it.
    class EepromWrite < StandardError; end

    # leds is replaced, never changed in place, so a reference a test holds
    # stays as it was. attempts counts every write_feature and read_feature
    # call, failed or not; writes_by_id counts the writes recorded and
    # reads_by_id the reads that returned a well formed reply, per report ID.
    attr_reader :device, :writes, :stream, :attempts, :writes_by_id, :reads_by_id
    attr_accessor :leds

    def initialize(device, mode: 2, info_blocks: { 1 => "".b, 2 => "".b }, gone: false, **failures)
      @device = device
      @mode = mode
      @info_blocks = info_blocks
      @gone = gone
      @failures_left = check_failures(failures)
      @leds = Array.new(8, Blinkstick::Colour::OFF)
      @closed = false
      start_records
    end

    # Records the report one byte at a time, yielding the thread between
    # bytes, so two writes that are not serialised by the caller interleave
    # in #stream. There is deliberately no lock here. Refuses EEPROM reports
    # outright, failing whichever test sent one.
    def write_feature(report)
      raise EepromWrite, "report #{report.getbyte(0)} writes EEPROM" if EEPROM_IDS.include?(report.getbyte(0))

      start(:fail_writes)
      report.each_byte do |byte|
        @stream << byte
        Thread.pass
      end
      @writes << report
      apply(report)
    end

    # Builds the reply one LED at a time, yielding the thread between them
    # and again before returning, so a read that is not serialised against
    # writes by the caller can see two frames mixed. Never touches #stream,
    # which is for writes. There is deliberately no lock here.
    def read_feature(report_id, size)
      start(:fail_reads)
      reply = reply_for(report_id)
      Thread.pass
      return reply.byteslice(0, size - 1) if use_up?(:short_reads)
      return reply.dup.tap { |bytes| bytes.setbyte(0, report_id ^ 0xff) } if use_up?(:wrong_id_reads)

      @reads_by_id[report_id] += 1
      reply
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end

    private

    def check_failures(failures)
      unknown = failures.keys - FAILURES
      raise ArgumentError, "unknown fake switches: #{unknown.inspect}" unless unknown.empty?

      Hash.new(0).merge(failures)
    end

    def start_records
      @writes = []
      @stream = []
      @attempts = 0
      @writes_by_id = Hash.new(0)
      @reads_by_id = Hash.new(0)
    end

    # The checks every transfer makes before doing anything.
    def start(failure)
      raise Blinkstick::ClosedError, "fake handle closed" if @closed

      @attempts += 1
      raise Blinkstick::DisconnectedError, "#{device.serial} unplugged" if @gone
      raise Blinkstick::Backend::TransferFailed, "#{device.serial} busy" if use_up?(failure)
    end

    # @return [Boolean] true, using one up, while the named failure has any left
    def use_up?(failure)
      (@failures_left[failure] -= 1) >= 0
    end

    def reply_for(report_id)
      case report_id
      when Report::FRAME_ID then frame_reply
      when Report::MODE_ID then [Report::MODE_ID, @mode].pack("C*")
      when 2, 3 then info_block_reply(report_id)
      else raise ArgumentError, "the fake has no report #{report_id}"
      end
    end

    # Looks @leds up afresh for each LED, so a write landing part way
    # through shows up in the later LEDs only.
    def frame_reply
      Report.frame(Array.new(8) do |i|
        Thread.pass
        @leds[i]
      end)
    end

    def info_block_reply(report_id)
      [report_id].pack("C") + @info_blocks.fetch(report_id - 1).b.ljust(Report::INFO_BLOCK_SIZE - 1, "\0")
    end

    # Mirrors the LED state a recorded report leaves on the stick.
    def apply(report)
      id = report.getbyte(0)
      @writes_by_id[id] += 1
      case id
      when Report::FRAME_ID then @leds = Report.decode_frame(report, 8)
      when Report::LED_ID then @leds = @leds.dup.tap { |leds| leds[report.getbyte(2)] = rgb(report) }
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

  # @param switches [Hash] passed to every Handle this backend opens
  def initialize(*devices, busy: false, permission_denied: false, **switches)
    @devices = devices
    @busy = busy
    @permission_denied = permission_denied
    @switches = switches
    @handles = []
  end

  def list
    @devices
  end

  def open(device)
    raise Blinkstick::BusyError, "#{device.serial} is seized by another program" if @busy
    raise Blinkstick::PermissionError, "#{device.serial}: permission denied" if @permission_denied

    Handle.new(device, **@switches).tap { |handle| @handles << handle }
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
