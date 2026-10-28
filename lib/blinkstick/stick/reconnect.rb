# frozen_string_literal: true

module Blinkstick
  class Stick
    # How a {Stick} talks to its handle: under its lock, with retries, and
    # finding the stick again after it was unplugged (ported from
    # go-blinkstick's transferLocked and reconnectLocked). When a transfer
    # runs out of attempts or the handle says the stick is gone, the handle is
    # dropped, the stick reopened by serial, the last frame repainted and the
    # transfer run again. Everything here runs under the Stick's lock.
    #
    # @api private
    module Reconnect
      private

      # Holds the lock across every attempt and any reconnect, so transfers
      # from other threads cannot land in between.
      def transfer(what, frame_write: false, &)
        locked { with_reconnect(what, frame_write:, &) }
      end

      # Holds the lock for one call, refusing a closed stick. Each call may
      # reconnect once, however many transfers it makes.
      def locked
        @mutex.synchronize do
          raise ClosedError, "#{info.serial} is closed" if @closed

          @reconnected = false
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

          raise DisconnectedError, "#{info.serial.inspect} stopped responding: #{attempt} #{what} failed in a row"
        end
      end

      # Runs one transfer, reconnecting once if it fails. A call that makes
      # several transfers reconnects at most once in all: a later failure in
      # the same call raises and keeps the new handle. BusyError,
      # PermissionError and ClosedError pass through untouched.
      #
      # @param what [String] "reads" or "writes", for the error message
      # @param frame_write [Boolean] true when the transfer is a whole frame
      #   write, which repainting the old frame first would only flash
      # @raise [DisconnectedError] when the transfer fails and reconnecting
      #   cannot be tried, fails, or does not help
      def with_reconnect(what, frame_write: false, &)
        if @handle
          begin
            return with_retries(what, &)
          rescue DisconnectedError
            raise if @reopen.nil? || @reconnected

            drop_handle
          end
        end
        reconnect(repaint: !frame_write)
        with_retries(what, &)
      end

      # Reopens the stick and repaints the last frame, if asked and there is
      # one. Leaves no handle when either fails.
      #
      # @raise [DisconnectedError] naming the cause when either fails
      def reconnect(repaint:)
        @reconnected = true
        adopt(reopen_handle)
        repaint_last if repaint && @last
      end

      # The reopen's own message already names the serial (or says there is
      # none), so it is not repeated here.
      #
      # @return [#write_feature, #read_feature, #close] a fresh handle
      # @raise [DisconnectedError] wrapping whatever stopped the reopen
      def reopen_handle
        @reopen.call
      rescue Error => e
        raise DisconnectedError, "could not reconnect: #{e.message}"
      end

      # Sends the last frame again exactly as it was sent: already limited,
      # so not limited again, and flipped if inverse is on. The failure's own
      # message names the stick, so the serial is not repeated here.
      #
      # @raise [DisconnectedError] wrapping the failure, with the handle dropped
      def repaint_last
        report = Report.frame(@last.map { |colour| flipped(colour) })
        with_retries("writes") { @handle.write_feature(report) }
      rescue Error => e
        drop_handle
        raise DisconnectedError, "reconnected, but repainting the last frame failed: #{e.message}"
      end

      # Takes a new handle, moving the finaliser onto it.
      def adopt(handle)
        @handle = handle
        ObjectSpace.undefine_finalizer(self)
        ObjectSpace.define_finalizer(self, self.class.releaser(handle))
      end

      # Closes the handle, ignoring any error doing so, and forgets it along
      # with its finaliser.
      def drop_handle
        handle = @handle
        @handle = nil
        ObjectSpace.undefine_finalizer(self)
        begin
          handle.close
        rescue Error
          nil
        end
      end
    end
  end
end
