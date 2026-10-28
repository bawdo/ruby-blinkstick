# frozen_string_literal: true

module Blinkstick
  # An open BlinkStick. Get one from {Blinkstick.open}.
  #
  # A Stick is safe to share between threads: a Mutex serialises every
  # report written to or read from the device, and reads always ask the
  # stick (nothing is cached). A stick that is garbage collected without
  # {#close} still releases its OS handle, but call {#close} (or use the
  # block form of {Blinkstick.open}) rather than relying on that.
  class Stick
    include Eeprom
    include Handover
    include Lighting

    # @return [Info] the identity of this stick
    attr_reader :info

    # @api private
    # @param handle [#write_feature, #read_feature, #close] an open backend handle
    # @param info [Info]
    def initialize(handle, info)
      @handle = handle
      @info = info
      @mutex = Mutex.new
      @closed = false
      @limit = 255
      @inverse = false
      @last = nil
      ObjectSpace.define_finalizer(self, self.class.releaser(handle))
    end

    # Builds the finaliser here, not in an instance method, so it holds the
    # handle only and the Stick itself can still be collected.
    #
    # @api private
    # @param handle [#close]
    # @return [Proc]
    def self.releaser(handle)
      proc do
        handle.close
      rescue Error
        nil
      end
    end

    # Sets every LED to one colour.
    #
    # @param colour [Colour, String, Symbol, Array<Integer>] anything {Colour.parse} takes
    # @raise [InvalidColourError] before anything is sent, when colour is not a colour
    # @raise [ClosedError] after {#close}
    # @raise [BusyError] when another program holds the stick mid-transfer
    # @raise [PermissionError] when the system refuses access mid-transfer
    # @raise [DisconnectedError] when the stick stops responding
    def colour=(colour)
      write_frame([Colour.parse(colour)] * info.model.leds)
    end

    # Sets one LED, leaving the others as they are.
    #
    # @param index [Integer] LED index, 0 to one less than the model's LED count (a Nano takes 0 or 1, a Square 0 to 7)
    # @param colour [Colour, String, Symbol, Array<Integer>] anything {Colour.parse} takes
    # @return [Colour, String, Symbol, Array<Integer>] colour, as Ruby assignment does
    # @raise [IndexError] when index is not an Integer within the model's LEDs
    # @raise [InvalidColourError] when colour is not a colour (both checked before anything is sent)
    # @raise [ClosedError] after {#close}
    # @raise [BusyError] when another program holds the stick mid-transfer
    # @raise [PermissionError] when the system refuses access mid-transfer
    # @raise [DisconnectedError] when the stick stops responding
    def []=(index, colour)
      check_index(index)
      write_led(index, Colour.parse(colour))
      colour
    end

    # Sets every LED at once, one colour each, in a single report.
    #
    # @param colours [Array<Colour, String, Symbol, Array<Integer>>] exactly one per LED of the model
    # @raise [TypeError] when colours is not array like
    # @raise [ArgumentError] when colours has the wrong length
    # @raise [InvalidColourError] when any entry is not a colour
    # @raise [ClosedError] after {#close}
    # @raise [BusyError] when another program holds the stick mid-transfer
    # @raise [PermissionError] when the system refuses access mid-transfer
    # @raise [DisconnectedError] when the stick stops responding
    def frame=(colours)
      list = Array.try_convert(colours)
      raise TypeError, "frame must be an Array of colours, got #{colours.class}" if list.nil?

      model = info.model
      unless list.size == model.leds
        raise ArgumentError, "a #{model.name} has #{model.leds} LEDs, got #{list.size} colours"
      end

      write_frame(list.map { |colour| Colour.parse(colour) })
    end

    # Reads the LED mode from the stick.
    #
    # @return [Symbol, Integer] :rgb, :rgb_inverse, :ws2812 or :ws2812_mirror,
    #   or the raw byte for a mode the gem does not know
    # @raise [ClosedError] after {#close}
    # @raise [BusyError] when another program holds the stick mid-transfer
    # @raise [PermissionError] when the system refuses access mid-transfer
    # @raise [DisconnectedError] when the stick stops responding
    def mode
      Report.decode_mode(read(Report::MODE_ID, Report::MODE_SIZE))
    end

    # Reads a user data block from the stick.
    #
    # @param number [Integer] 1 or 2
    # @return [String] frozen binary String, up to 32 bytes, trailing NULs removed
    # @raise [ArgumentError] before anything is sent, when number is not 1 or 2
    # @raise [ClosedError] after {#close}
    # @raise [BusyError] when another program holds the stick mid-transfer
    # @raise [PermissionError] when the system refuses access mid-transfer
    # @raise [DisconnectedError] when the stick stops responding
    def info_block(number)
      Report.decode_info_block(read(Report.info_block_id(number), Report::INFO_BLOCK_SIZE))
    end

    # Turns every LED off.
    #
    # @return [void]
    # @raise [ClosedError] after {#close}
    # @raise [BusyError] when another program holds the stick mid-transfer
    # @raise [PermissionError] when the system refuses access mid-transfer
    # @raise [DisconnectedError] when the stick stops responding
    def off
      self.colour = Colour::OFF
      nil
    end

    # Releases the stick. Calling it again does nothing.
    #
    # @return [void]
    def close
      @mutex.synchronize do
        next if @closed

        @closed = true
        ObjectSpace.undefine_finalizer(self)
        @handle.close
      end
      nil
    end

    # @return [Boolean] true once {#close} has been called
    def closed?
      @closed
    end

    private

    # @raise [IndexError] unless index is an Integer from 0 to the model's LEDs
    def check_index(index)
      model = info.model
      return if index.is_a?(Integer) && index >= 0 && index < model.leds

      raise IndexError, "LED #{index.inspect} is out of range: a #{model.name} has #{model.leds} LEDs"
    end

    # Sends a report.
    def write(report)
      transfer("writes") { @handle.write_feature(report) }
    end

    # Reads a report. A reply that is short or carries another report's ID
    # counts as a failed attempt, so it is retried and never decoded.
    #
    # @return [String] at least size bytes, the first being report_id
    def read(report_id, size)
      transfer("reads") { fetch(report_id, size) }
    end

    # One read attempt, checked. The caller holds the lock.
    def fetch(report_id, size)
      reply = @handle.read_feature(report_id, size)
      unless reply.bytesize >= size && reply.getbyte(0) == report_id
        raise Backend::TransferFailed,
              "report #{report_id}: got #{reply.bytesize} of #{size} bytes, ID #{reply.getbyte(0).inspect}"
      end

      reply
    end

    # Holds the lock across every attempt, so transfers from other threads
    # cannot land in between.
    def transfer(what, &)
      locked { with_retries(what, &) }
    end

    # Holds the lock, refusing a closed stick.
    def locked
      @mutex.synchronize do
        raise ClosedError, "#{info.serial} is closed" if @closed

        yield
      end
    end

    # Runs the block up to Backend::ATTEMPTS times while it raises
    # TransferFailed. The caller must hold the lock.
    def with_retries(what)
      attempt = 0
      begin
        attempt += 1
        yield
      rescue Backend::TransferFailed
        retry if attempt < Backend::ATTEMPTS

        raise DisconnectedError, "#{info.serial} stopped responding: #{attempt} #{what} failed in a row"
      end
    end
  end
end
