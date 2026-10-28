# frozen_string_literal: true

require_relative "errors"

module Blinkstick
  # An immutable colour with 8 bits per channel.
  #
  #   Blinkstick::Colour.parse("#ff8800")
  #   Blinkstick::Colour.parse("255,136,0")
  #   Blinkstick::Colour.parse(:cornflowerblue)
  Colour = Data.define(:red, :green, :blue) do
    # @raise [InvalidColourError] unless each channel is an Integer from 0 to 255
    def initialize(red:, green:, blue:)
      [red, green, blue].each do |channel|
        next if channel.is_a?(Integer) && channel.between?(0, 255)

        raise InvalidColourError, "invalid colour channel #{channel.inspect}"
      end
      super
    end

    # Converts a value to a Colour.
    #
    # Accepts a Colour (returned as is), a Symbol or String CSS colour name in
    # any case, hex ("#rgb" or "#rrggbb", with or without the "#"), a decimal
    # "r,g,b" String, or an Array of three Integers.
    #
    # @param input [Colour, String, Symbol, Array<Integer>]
    # @return [Colour]
    # @raise [InvalidColourError] when the input is not a colour
    def self.parse(input)
      case input
      when Colour then input
      when Symbol then lookup(input.name.downcase) || invalid(input)
      when Array then from_array(input)
      when String then from_string(input)
      else invalid(input)
      end
    end

    # @return [Array<String>] every CSS colour name {parse} accepts, lower case and sorted
    def self.names
      NAMES
    end

    # Picks a random colour.
    #
    # Without +vivid+ each channel is uniform from 0 to 255, so many results are
    # muted. With +vivid+ the colour is one of the 1530 fully saturated hues:
    # one channel is 255 and another is 0. Not suitable for anything security
    # related.
    #
    # @param vivid [Boolean] pick only fully saturated hues
    # @param random [#rand] the generator, anything responding to +rand(n)+
    # @return [Colour]
    def self.random(vivid: false, random: Random)
      return hue(random.rand(Colour::HUES)) if vivid

      new(red: random.rand(256), green: random.rand(256), blue: random.rand(256))
    end

    # @return [Colour] the colour with each channel replaced by 255 minus its value
    def inverse
      with(red: 255 - red, green: 255 - green, blue: 255 - blue)
    end

    # @return [String] the colour as lower case "#rrggbb"
    def hex
      format("#%<r>02x%<g>02x%<b>02x", r: red, g: green, b: blue)
    end

    alias_method :to_s, :hex

    class << self
      private

      # Port of go-blinkstick's hue: step +step+ (0...HUES) of the wheel,
      # running red, yellow, green, cyan, blue, magenta and back towards red.
      def hue(step)
        offset = step % 255
        case step / 255
        when 0 then new(red: 255, green: offset, blue: 0)
        when 1 then new(red: 255 - offset, green: 255, blue: 0)
        when 2 then new(red: 0, green: 255, blue: offset)
        when 3 then new(red: 0, green: 255 - offset, blue: 255)
        when 4 then new(red: offset, green: 0, blue: 255)
        else new(red: 255, green: 0, blue: 255 - offset)
        end
      end

      def lookup(name)
        COLOUR_NAMES[name]
      end

      def from_array(array)
        invalid(array) unless array.size == 3 && array.all?(Integer)
        new(red: array[0], green: array[1], blue: array[2])
      rescue InvalidColourError
        invalid(array)
      end

      # Bytes that are invalid in the String's encoding are not a colour, and
      # would otherwise raise from strip or the regexps below.
      def from_string(input)
        return invalid(input) unless input.valid_encoding?

        text = input.strip
        return from_hex(input, text.delete_prefix("#")) if text.start_with?("#")

        lookup(text.downcase) || (text.include?(",") ? from_decimals(input, text) : from_hex(input, text))
      end

      def from_hex(input, digits)
        digits = digits.chars.map { |digit| digit * 2 }.join if digits.size == 3
        invalid(input) unless digits.match?(/\A\h{6}\z/)
        value = digits.to_i(16)
        new(red: value >> 16, green: (value >> 8) & 0xff, blue: value & 0xff)
      end

      def from_decimals(input, text)
        parts = text.split(",", -1).map(&:strip)
        invalid(input) unless parts.size == 3 && parts.all?(/\A\d{1,3}\z/)
        red, green, blue = parts.map(&:to_i)
        new(red:, green:, blue:)
      rescue InvalidColourError
        invalid(input)
      end

      def invalid(input)
        raise InvalidColourError, "invalid colour #{input.is_a?(Symbol) ? input.name.inspect : input.inspect}"
      end
    end
  end

  # Number of fully saturated hues: six segments of 255 steps.
  Colour::HUES = 6 * 255

  # Colour with every channel off.
  Colour::OFF = Colour.new(red: 0, green: 0, blue: 0)
end

require_relative "colour_names"
