# frozen_string_literal: true

module Blinkstick
  # An open BlinkStick. Get one from {Blinkstick.open}.
  #
  # A Stick is safe to share between threads: a Mutex serialises every
  # report sent to the device. A stick that is garbage collected without
  # {#close} still releases its OS handle, but call {#close} (or use the
  # block form of {Blinkstick.open}) rather than relying on that.
  class Stick
    # @return [Info] the identity of this stick
    attr_reader :info

    # @api private
    # @param handle [#write_feature, #close] an open backend handle
    # @param info [Info]
    def initialize(handle, info)
      @handle = handle
      @info = info
      @mutex = Mutex.new
      @closed = false
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
    # @raise [DisconnectedError] when the stick stops responding
    def colour=(colour)
      write(Report.frame([Colour.parse(colour)] * info.model.leds))
    end

    # Turns every LED off.
    #
    # @return [void]
    # @raise [ClosedError] after {#close}
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

    # Holds the lock across every attempt, so reports from other threads
    # cannot land in between.
    def write(report)
      @mutex.synchronize do
        raise ClosedError, "#{info.serial} is closed" if @closed

        transfer(report)
      end
    end

    # Tries up to Backend::ATTEMPTS times while the handle says the failure
    # is transient. The caller must hold the lock.
    def transfer(report)
      attempt = 0
      begin
        attempt += 1
        @handle.write_feature(report)
      rescue Backend::TransferFailed
        retry if attempt < Backend::ATTEMPTS

        raise DisconnectedError, "#{info.serial} stopped responding: #{attempt} writes failed in a row"
      end
    end
  end
end
