# frozen_string_literal: true

module Blinkstick
  class Stick
    # The LED write path of a {Stick}: the brightness limit, inverse, and the
    # last frame written (which a reconnect repaints). All state is guarded by
    # the Stick's lock.
    #
    # @api private
    module Lighting
      # @return [Integer] the brightness limit, 0 to 255 (255 by default)
      def brightness_limit
        @mutex.synchronize { @limit }
      end

      # Caps every channel of every write from now on: a channel v is sent as
      # <tt>v * limit / 255</tt> (Integer division). Reads return what the stick
      # holds, so they are never scaled back up. Per Stick, not stored on the
      # device, and it does not repaint what is already lit.
      #
      # @param limit [Integer] 0 to 255
      # @raise [ArgumentError] unless limit is an Integer from 0 to 255
      def brightness_limit=(limit)
        raise ArgumentError, "brightness limit must be an Integer from 0 to 255, got #{limit.inspect}" unless
          limit.is_a?(Integer) && limit.between?(0, 255)

        @mutex.synchronize { @limit = limit }
      end

      # @return [Boolean] whether writes are flipped to 255 minus the value
      def inverse?
        @mutex.synchronize { @inverse }
      end

      # Flips every channel written from now on to <tt>255 - v</tt>, after the
      # brightness limit, for LEDs wired so 255 is off. Reads flip back, so
      # {Stick#frame} and {Stick#[]} return what was written. It does not
      # repaint, so set it before setting LEDs. Not the firmware inverse mode.
      #
      # @param on [Object] truthiness is stored as true or false
      def inverse=(on)
        @mutex.synchronize { @inverse = on ? true : false }
      end

      # Reads every LED back from the stick. Nothing is cached: each call asks
      # the stick. Values are what the stick holds (after the brightness limit),
      # flipped back when {#inverse?} is on.
      #
      # @return [Array<Colour>] frozen, one per LED of the model
      # @raise [ClosedError] after {#close}
      # @raise [BusyError] when another program holds the stick mid-transfer
      # @raise [PermissionError] when the system refuses access mid-transfer
      # @raise [DisconnectedError] when the stick stops responding and reconnecting to it fails
      def frame
        transfer("reads") { flipped_frame }
      end

      # Reads one LED back from the stick, by reading the whole frame.
      #
      # @param index [Integer] LED index, 0 to one less than the model's LED count (Nano 0 or 1, Square 0 to 7)
      # @return [Colour]
      # @raise [IndexError] before anything is sent, when index is not an Integer within the model's LEDs
      # @raise [ClosedError] after {#close}
      # @raise [BusyError] when another program holds the stick mid-transfer
      # @raise [PermissionError] when the system refuses access mid-transfer
      # @raise [DisconnectedError] when the stick stops responding and reconnecting to it fails
      def [](index)
        check_index(index)
        frame.fetch(index)
      end

      private

      # Scales, flips and sends a whole frame, then records it (scaled, not
      # flipped) as the last frame. Takes the lock itself.
      #
      # @param colours [Array<Colour>] one per LED of the model
      # @param scale [Boolean] false to skip the brightness limit
      def write_frame(colours, scale: true)
        transfer("writes", frame_write: true) do
          limited = scale ? colours.map { |colour| scaled(colour) } : colours.dup
          @handle.write_feature(Report.frame(limited.map { |colour| flipped(colour) }))
          @last = limited.freeze
        end
      end

      # Sends one LED, seeding the last frame from the stick first when
      # nothing has been written yet. One lock hold covers both.
      def write_led(index, colour)
        locked do
          @last ||= with_reconnect("reads") { flipped_frame }
          limited = scaled(colour)
          with_reconnect("writes") { @handle.write_feature(Report.led(index, flipped(limited))) }
          @last = @last.dup.tap { |frame| frame[index] = limited }.freeze
        end
      end

      # One read of the frame, flipped back if inverse. The caller holds the lock.
      def flipped_frame
        frame = Report.decode_frame(fetch(Report::FRAME_ID, Report::FRAME_SIZE), info.model.leds)
        @inverse ? frame.map(&:inverse).freeze : frame
      end

      # Applies the brightness limit, for a caller that does not hold the lock.
      def brightness_scaled(colour)
        @mutex.synchronize { scaled(colour) }
      end

      # Applies the brightness limit. The caller holds the lock.
      def scaled(colour)
        return colour if @limit == 255

        Colour.new(red: colour.red * @limit / 255, green: colour.green * @limit / 255,
                   blue: colour.blue * @limit / 255)
      end

      def flipped(colour)
        @inverse ? colour.inverse : colour
      end
    end
  end
end
