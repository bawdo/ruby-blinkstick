# frozen_string_literal: true

module Blinkstick
  class Stick
    # The parts of a {Stick} that write the stick's EEPROM: its name, its
    # user data blocks and its LED mode. EEPROM wears with every write, so
    # none of these belongs in a loop.
    module Eeprom
      # Modes this gem will set, by the byte the stick stores. The BlinkStick
      # Pro modes (0 and 1) are refused.
      SETTABLE_MODES = { ws2812: 2, ws2812_mirror: 3 }.freeze
      private_constant :SETTABLE_MODES

      # Writes a user data block, padded with NULs to 32 bytes. This writes
      # EEPROM, which wears with use, so do not call it in a loop.
      #
      # @param number [Integer] 1 or 2 (block 1 holds the {#name})
      # @param bytes [String] at most 32 bytes (its raw bytes are stored, whatever its encoding)
      # @return [nil]
      # @raise [ArgumentError] before anything is sent, when number is not 1 or 2 or bytes is over 32 bytes
      # @raise [TypeError] before anything is sent, when bytes is not a String
      # @raise [ClosedError] after {#close}
      # @raise [BusyError] when another program holds the stick mid-transfer
      # @raise [PermissionError] when the system refuses access mid-transfer
      # @raise [DisconnectedError] when the stick stops responding and reconnecting to it fails
      def write_info_block(number, bytes)
        data = String.try_convert(bytes)
        raise TypeError, "info block data must be a String, got #{bytes.class}" if data.nil?

        write(Report.info_block(number, data))
        nil
      end

      # Reads the name stored on the stick (info block 1, as the official
      # BlinkStick tools do). Another tool may have stored bytes that are not
      # valid UTF-8 or that are control characters, and they are returned as
      # they are: sanitise the name before printing it to a terminal.
      #
      # @return [String] frozen, tagged UTF-8, "" when no name is set
      # @raise [ClosedError] after {#close}
      # @raise [BusyError] when another program holds the stick mid-transfer
      # @raise [PermissionError] when the system refuses access mid-transfer
      # @raise [DisconnectedError] when the stick stops responding and reconnecting to it fails
      def name
        info_block(1).dup.force_encoding(Encoding::UTF_8).freeze
      end

      # Stores a name on the stick, replacing any name already there. This
      # writes EEPROM, which wears with use, so do not call it in a loop.
      #
      # @param name [String] UTF-8 of at most 32 bytes with no NUL; "" clears the name
      # @return [String] name, as Ruby assignment does
      # @raise [TypeError] before anything is sent, when name is not a String
      # @raise [ArgumentError] before anything is sent, when name is not valid UTF-8, holds a NUL or is over 32 bytes
      # @raise [ClosedError] after {#close}
      # @raise [BusyError] when another program holds the stick mid-transfer
      # @raise [PermissionError] when the system refuses access mid-transfer
      # @raise [DisconnectedError] when the stick stops responding and reconnecting to it fails
      def name=(name)
        raise TypeError, "name must be a String, got #{name.class}" unless name.is_a?(String)

        check_name(name)
        write_info_block(1, name)
        name
      end

      # Sets the LED mode, unless the stick is already in it. This writes
      # EEPROM, which wears with use, so call it once and not in a loop. The
      # read and the write happen under one lock, so no other thread's
      # transfer lands between them.
      #
      # @param mode [Symbol, Integer] :ws2812 (or 2) or :ws2812_mirror (or 3).
      #   The BlinkStick Pro modes (0, 1, :rgb, :rgb_inverse) are refused.
      # @return [Symbol, Integer] mode, as Ruby assignment does
      # @raise [ArgumentError] before anything is sent, when mode is not :ws2812, :ws2812_mirror, 2 or 3
      # @raise [ClosedError] after {#close}
      # @raise [BusyError] when another program holds the stick mid-transfer
      # @raise [PermissionError] when the system refuses access mid-transfer
      # @raise [DisconnectedError] when the stick stops responding and reconnecting to it fails
      def mode=(mode)
        byte = settable_mode(mode)
        locked do
          current = with_reconnect("reads") { fetch(Report::MODE_ID, Report::MODE_SIZE) }
          with_reconnect("writes") { @handle.write_feature(Report.mode(byte)) } unless current.getbyte(1) == byte
        end
        mode
      end

      private

      # @raise [ArgumentError] unless name is UTF-8 without NULs, 32 bytes at most
      def check_name(name)
        bytes = name.b
        unless bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding? && !bytes.include?("\0")
          raise ArgumentError, "name must be UTF-8 without NUL characters"
        end
        return if bytes.bytesize <= Report::INFO_BLOCK_SIZE - 1

        raise ArgumentError, "name is #{bytes.bytesize} bytes, the most a stick holds is #{Report::INFO_BLOCK_SIZE - 1}"
      end

      # @return [Integer] the mode byte
      # @raise [ArgumentError] unless mode is :ws2812, :ws2812_mirror, 2 or 3
      def settable_mode(mode)
        byte = mode.is_a?(Integer) ? mode : SETTABLE_MODES[mode]
        return byte if SETTABLE_MODES.value?(byte)

        raise ArgumentError, "mode must be :ws2812, :ws2812_mirror, 2 or 3, got #{mode.inspect} " \
                             "(the other modes are for the BlinkStick Pro, which this gem does not support)"
      end
    end
  end
end
