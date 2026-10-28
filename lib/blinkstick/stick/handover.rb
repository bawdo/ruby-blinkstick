# frozen_string_literal: true

module Blinkstick
  class Stick
    # Passing an open handle from one {Stick} to another.
    module Handover
      # Gives up the open handle without closing it, leaving this stick closed
      # and its finaliser removed, so the handle can go to a new Stick.
      #
      # @api private
      # @return [#write_feature, #read_feature, #close] the handle, still open
      def detach
        @mutex.synchronize do
          @closed = true
          ObjectSpace.undefine_finalizer(self)
          @handle
        end
      end
    end
  end
end
