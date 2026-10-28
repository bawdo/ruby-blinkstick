# frozen_string_literal: true

# The simulated open device behind FakeBackend.
class FakeBackend
  # The EEPROM side of a Handle: refusing, applying and replying.
  module Eeprom
    # Reports kept in EEPROM: info blocks 1 and 2, and the mode.
    EEPROM_IDS = [2, 3, Blinkstick::Report::MODE_ID].freeze

    # Raised for a write the gem must never send. Deliberately outside
    # Blinkstick::Error, so no rescue in the gem or assert_raises in a test
    # can swallow it.
    class EepromWrite < StandardError; end

    private

    def check_eeprom(report)
      id = report.getbyte(0)
      raise EepromWrite, "report #{id} writes EEPROM" if EEPROM_IDS.include?(id) && !@eeprom_writes
    end

    def info_block_reply(report_id)
      size = Blinkstick::Report::INFO_BLOCK_SIZE - 1
      [report_id].pack("C") + @state.info_blocks.fetch(report_id - 1).b.ljust(size, "\0")
    end

    # @return [Boolean] true, using one up, while the device is still busy after a mode write
    def storing_mode?
      return false unless @state.busy_left.positive?

      @state.busy_left -= 1
      true
    end

    # A mode write leaves the device refusing the next busy_after_mode
    # transfers, from any handle, as a real stick does for 12 to 15 ms.
    def apply_eeprom(id, report)
      if id == Blinkstick::Report::MODE_ID
        @state.mode = report.getbyte(1)
        @state.busy_left = @busy_after_mode
      elsif EEPROM_IDS.include?(id)
        @state.info_blocks = @state.info_blocks.merge(id - 1 => report.byteslice(1..).b)
      end
    end
  end

  # A simulated open device.
  #
  # Switches, all optional: fail_writes, fail_reads, short_reads and
  # wrong_id_reads are how many attempts in a row go wrong before the fake
  # behaves (raising TransferFailed, returning one byte too few, or
  # returning the wrong first byte); gone makes every transfer raise
  # DisconnectedError; busy_after_mode is how many transfers in a row the
  # device refuses with TransferFailed after this handle writes the mode,
  # whichever handle makes them (as IOKit reports kIOReturnNotResponding
  # while a real stick stores its mode). The LEDs, mode and info blocks live in the device's
  # state, so they survive reopening and are shared by every handle on one
  # serial; eeprom_writes lets reports 2, 3 and 4 through.
  class Handle
    include Eeprom

    Report = Blinkstick::Report

    FAILURES = %i[fail_writes fail_reads short_reads wrong_id_reads].freeze

    # attempts counts every write_feature and read_feature call, failed or
    # not; writes_by_id counts the writes recorded and reads_by_id the reads
    # that returned a well formed reply, per report ID.
    attr_reader :device, :writes, :stream, :attempts, :writes_by_id, :reads_by_id

    def initialize(device, state, eeprom_writes: false, gone: false, **failures)
      @device = device
      @state = state
      @eeprom_writes = eeprom_writes
      @gone = gone
      @busy_after_mode = failures.delete(:busy_after_mode) || 0
      @failures_left = check_failures(failures)
      @closed = false
      start_records
    end

    # Records the report one byte at a time, yielding the thread between
    # bytes, so two writes that are not serialised by the caller interleave
    # in #stream. There is deliberately no lock here. Refuses EEPROM reports
    # outright, failing whichever test sent one.
    def write_feature(report)
      check_eeprom(report)

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

    # Called when the device is unplugged: this handle is gone for good, even
    # if the device comes back.
    def unplug
      @gone = true
    end

    # @return [Array<Colour>] the device's LEDs, whichever handle set them
    def leds
      @state.leds
    end

    def leds=(colours)
      @state.leds = colours
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
      raise Blinkstick::Backend::TransferFailed, "#{device.serial} storing its mode" if storing_mode?
    end

    # @return [Boolean] true, using one up, while the named failure has any left
    def use_up?(failure)
      (@failures_left[failure] -= 1) >= 0
    end

    def reply_for(report_id)
      case report_id
      when Report::FRAME_ID then frame_reply
      when Report::MODE_ID then [Report::MODE_ID, @state.mode].pack("C*")
      when 2, 3 then info_block_reply(report_id)
      else raise ArgumentError, "the fake has no report #{report_id}"
      end
    end

    # Looks the LEDs up afresh for each one, so a write landing part way
    # through shows up in the later LEDs only.
    def frame_reply
      Report.frame(Array.new(8) do |i|
        Thread.pass
        leds[i]
      end)
    end

    # Mirrors the LED state a recorded report leaves on the stick.
    def apply(report)
      id = report.getbyte(0)
      @writes_by_id[id] += 1
      case id
      when Report::FRAME_ID then self.leds = Report.decode_frame(report, 8)
      when Report::LED_ID then self.leds = leds.dup.tap { |colours| colours[report.getbyte(2)] = rgb(report) }
      else apply_eeprom(id, report)
      end
    end

    def rgb(report)
      Blinkstick::Colour.new(red: report.getbyte(3), green: report.getbyte(4), blue: report.getbyte(5))
    end
  end
end
