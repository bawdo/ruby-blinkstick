# frozen_string_literal: true

require_relative "../../blinkstick"

module Blinkstick
  module Backend
    # The Linux backend. It finds sticks by reading sysfs and talks to them
    # through their /dev/hidraw node with the HIDIOCSFEATURE ioctl, so it
    # needs nothing beyond the standard library.
    #
    # @api private
    class Hidraw
      # The ioctl request number for HIDIOCSFEATURE of the given length:
      # direction read/write (3), size, type 'H' (0x48) and number 6.
      #
      # @param length [Integer] report size in bytes
      # @return [Integer]
      def self.set_feature_request(length) # rubocop:disable Naming/AccessorMethodName
        # The name is the kernel's (HIDIOCSFEATURE), not a Ruby writer.
        (3 << 30) | (length << 16) | (0x48 << 8) | 0x06
      end

      # An open hidraw node.
      class Handle
        # @param io [#ioctl, #close] the open device node
        # @param serial [String, nil] named in error messages
        def initialize(io, serial: nil)
          @io = io
          @serial = serial
          @closed = false
        end

        # Sends a feature report.
        #
        # @param report [String] binary String whose first byte is the report ID
        # @raise [ClosedError] after {#close}
        # @raise [DisconnectedError] when the stick is unplugged
        # @raise [TransferFailed] for any other failed transfer
        def write_feature(report)
          raise ClosedError, "#{name} is closed" if @closed

          @io.ioctl(Hidraw.set_feature_request(report.bytesize), report.dup)
        rescue Errno::ENODEV, Errno::ENOENT, Errno::ESHUTDOWN => e
          raise DisconnectedError, "#{name} was unplugged (#{e.class})"
        rescue Errno::EACCES, Errno::EPERM => e
          raise PermissionError, "#{name}: #{e.message}. #{UDEV_HINT}"
        rescue SystemCallError => e
          raise TransferFailed, "#{name}: #{e.message}"
        end

        # Releases the node. Calling it again does nothing, and it never raises.
        #
        # @return [void]
        def close
          return if @closed

          @closed = true
          begin
            @io.close
          rescue IOError, SystemCallError
            nil
          end
        end

        private

        def name
          @serial || "the stick"
        end
      end

      UDEV_HINT = 'See the "Linux" section of the README (the udev rule) to grant access.'
      private_constant :UDEV_HINT

      # @param sysfs [String] where sysfs is mounted
      # @param dev [String] where the device nodes live
      def initialize(sysfs: "/sys", dev: "/dev")
        @sysfs = sysfs
        @dev = dev
      end

      # @return [Array<Device>] every BlinkStick attached, in hidraw order
      #   (hidraw2 before hidraw10)
      def list
        Dir.glob(File.join(@sysfs, "class/hidraw/hidraw*"))
           .sort_by { |entry| File.basename(entry).delete_prefix("hidraw").to_i }
           .filter_map { |entry| device_for(entry) }
      end

      # @param device [Device] a device from {#list}
      # @return [Handle]
      # @raise [NotFoundError, PermissionError, BusyError] when it cannot be opened
      # @raise [Error] when opening fails for any other reason
      def open(device)
        Handle.new(File.open(device.id, "r+b"), serial: device.serial)
      rescue SystemCallError => e
        raise open_error(e, device)
      end

      private

      def open_error(error, device)
        where = "#{device.serial} (#{device.id})"
        case error
        when Errno::ENOENT, Errno::ENODEV then NotFoundError.new("#{where} is no longer attached")
        when Errno::EACCES, Errno::EPERM then PermissionError.new("Permission denied opening #{where}. #{UDEV_HINT}")
        when Errno::EBUSY then BusyError.new("#{where} is in use by another program")
        else Error.new("Could not open #{where}: #{error.message}")
        end
      end

      def device_for(entry)
        hid = File.realpath(File.join(entry, "device"))
        uevent = parse_uevent(File.join(hid, "uevent"))
        return unless blinkstick?(uevent["HID_ID"])

        usb = File.expand_path("../..", hid)
        Device.new(id: File.join(@dev, File.basename(entry)), serial: text(uevent.fetch("HID_UNIQ", "")),
                   manufacturer: attribute(usb, "manufacturer"), product: attribute(usb, "product"),
                   release: attribute(usb, "bcdDevice").to_i(16))
      rescue SystemCallError
        nil
      end

      # Read in binary, so a device name that is not valid in the locale's
      # encoding (a UTF-8 "®" under LANG=C, say) cannot break parsing.
      def parse_uevent(path)
        File.readlines(path, chomp: true, mode: "rb").to_h { |line| line.split("=", 2).then { |k, v| [k, v.to_s] } }
      end

      # HID_ID is bus:vendor:product in hex.
      def blinkstick?(hid_id)
        _bus, vendor, product = hid_id.to_s.split(":")
        vendor.to_s.hex == VENDOR_ID && product.to_s.hex == PRODUCT_ID
      end

      def attribute(dir, file)
        text(File.binread(File.join(dir, file)).strip)
      rescue SystemCallError
        ""
      end

      # sysfs strings are UTF-8 by convention; invalid bytes become U+FFFD.
      def text(bytes)
        bytes.dup.force_encoding(Encoding::UTF_8).scrub
      end
    end
  end
end
