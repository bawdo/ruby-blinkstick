# frozen_string_literal: true

module Blinkstick
  class Stick
    # Passing an open handle from one {Stick} to another.
    #
    # @api private
    module Handover
      # Gives up the open handle without closing it, leaving this stick closed
      # and its finaliser removed, so the handle can go to a new Stick. A
      # closed stick no longer owns its handle, so it refuses.
      #
      # @api private
      # @return [#write_feature, #read_feature, #close] the handle, still open
      # @raise [ClosedError] after {Stick#close} or an earlier detach
      def detach
        @mutex.synchronize do
          raise ClosedError, "#{info.serial} is closed" if @closed

          @closed = true
          ObjectSpace.undefine_finalizer(self)
          @handle
        end
      end
    end
  end
end
