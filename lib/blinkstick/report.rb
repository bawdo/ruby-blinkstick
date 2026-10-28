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

    # Report ID of a single LED write.
    LED_ID = 5

    # Single LED report size in bytes: ID, channel, index, then R, G, B.
    LED_SIZE = 6

    # Builds report 5 for channel 0. Unlike the frame, the colour is R, G, B.
    #
    # @param index [Integer] LED index, 0 to 255
    # @param colour [Colour]
    # @return [String] frozen binary String of {LED_SIZE} bytes
    # @raise [ArgumentError] unless index is an Integer from 0 to 255
    def self.led(index, colour)
      raise ArgumentError, "LED index must be an Integer from 0 to 255, got #{index.inspect}" unless
        index.is_a?(Integer) && index.between?(0, 255)

      [LED_ID, 0, index, colour.red, colour.green, colour.blue].pack("C*").freeze
    end

    # Reads the first LEDs of a report 6 (G, R, B per slot).
    #
    # @param bytes [Array<Integer>, String] the {FRAME_SIZE} byte report
    # @param count [Integer] LEDs to decode, at most {FRAME_LEDS}
    # @return [Array<Colour>] frozen
    def self.decode_frame(bytes, count)
      bytes = bytes.bytes if bytes.is_a?(String)
      Array.new(count) do |i|
        green, red, blue = bytes[2 + (i * 3), 3]
        Colour.new(red:, green:, blue:)
      end.freeze
    end

    # Report ID of the LED mode.
    MODE_ID = 4

    # Mode report size in bytes: ID, then the mode.
    MODE_SIZE = 2

    # Device mode bytes and their names.
    MODES = { 0 => :rgb, 1 => :rgb_inverse, 2 => :ws2812, 3 => :ws2812_mirror }.freeze

    # @param bytes [Array<Integer>, String] the {MODE_SIZE} byte report
    # @return [Symbol, Integer] the mode name, or the raw byte when unknown
    def self.decode_mode(bytes)
      byte = bytes.is_a?(String) ? bytes.getbyte(1) : bytes[1]
      MODES.fetch(byte, byte)
    end

    # Info block report size in bytes: ID, then 32 data bytes.
    INFO_BLOCK_SIZE = 33

    # @param number [Integer] info block 1 or 2
    # @return [Integer] the report ID to read (2 or 3)
    # @raise [ArgumentError] unless number is 1 or 2
    def self.info_block_id(number)
      case number
      when 1 then 2
      when 2 then 3
      else raise ArgumentError, "info block must be 1 or 2, got #{number.inspect}"
      end
    end

    # @param bytes [Array<Integer>, String] the {INFO_BLOCK_SIZE} byte report
    # @return [String] frozen ASCII-8BIT text with trailing NULs removed
    def self.decode_info_block(bytes)
      bytes = bytes.bytes if bytes.is_a?(String)
      bytes[1, INFO_BLOCK_SIZE - 1].pack("C*").sub(/\0+\z/n, "").freeze
    end
  end
end
