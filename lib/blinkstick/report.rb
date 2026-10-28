# frozen_string_literal: true

module Blinkstick
  # Builds the HID feature report bytes the device understands.
  #
  # @api private
  module Report
    # Report ID of the LED frame.
    FRAME_ID = 6

    # Frame size in bytes: ID, channel, then 8 x (G, R, B).
    FRAME_SIZE = 26

    # LEDs addressable in one frame.
    FRAME_LEDS = 8

    # Builds report 6 for channel 0. The device wants each LED as G, R, B and
    # slots beyond the given colours are zero.
    #
    # @param colours [Array<Colour>] at most {FRAME_LEDS}
    # @return [String] frozen binary String of {FRAME_SIZE} bytes
    # @raise [ArgumentError] when given more than {FRAME_LEDS} colours
    def self.frame(colours)
      raise ArgumentError, "at most #{FRAME_LEDS} colours, got #{colours.size}" if colours.size > FRAME_LEDS

      bytes = [FRAME_ID, 0] + colours.flat_map { |c| [c.green, c.red, c.blue] }
      bytes.fill(0, bytes.size...FRAME_SIZE).pack("C*").freeze
    end
  end
end
