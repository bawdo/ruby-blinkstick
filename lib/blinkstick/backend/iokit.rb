# frozen_string_literal: true

require "ffi"
require_relative "../../blinkstick"

module Blinkstick
  module Backend
    # The macOS backend. It finds sticks with an IOHIDManager and sends
    # feature reports with IOHIDDeviceSetReport, calling IOKit and
    # CoreFoundation through ffi. Sticks are opened shared, never seized.
    #
    # CoreFoundation ownership follows Apple's Create rule: anything returned
    # by a Create or Copy call is released here, and anything returned by a
    # Get call is borrowed. Each listed device reference is retained, and
    # released by its FFI::AutoPointer once no {Device} refers to it. {#open}
    # takes a second retain that the {Handle} owns and releases on close, so
    # an open device outlives the AutoPointer whatever order finalisers run in.
    #
    # @api private
    class IOKit
      # kIOHIDOptionsTypeNone: open the device shared, never seized.
      OPEN_OPTIONS = 0

      # The IOKit and CoreFoundation functions this backend calls, and
      # helpers that make and read CF values.
      #
      # @api private
      module Native
        extend FFI::Library

        ffi_lib "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
                "/System/Library/Frameworks/IOKit.framework/IOKit"

        attach_function :cf_retain, :CFRetain, [:pointer], :pointer
        attach_function :cf_release, :CFRelease, [:pointer], :void
        attach_function :cf_get_type_id, :CFGetTypeID, [:pointer], :ulong
        attach_function :cf_string_get_type_id, :CFStringGetTypeID, [], :ulong
        attach_function :cf_number_get_type_id, :CFNumberGetTypeID, [], :ulong
        attach_function :cf_string_create_with_c_string, :CFStringCreateWithCString, %i[pointer string uint32], :pointer
        attach_function :cf_string_get_length, :CFStringGetLength, [:pointer], :long
        attach_function :cf_string_get_maximum_size_for_encoding, :CFStringGetMaximumSizeForEncoding,
                        %i[long uint32], :long
        attach_function :cf_string_get_c_string, :CFStringGetCString, %i[pointer pointer long uint32], :uchar
        attach_function :cf_number_create, :CFNumberCreate, %i[pointer long pointer], :pointer
        attach_function :cf_number_get_value, :CFNumberGetValue, %i[pointer long pointer], :uchar
        attach_function :cf_dictionary_create_mutable, :CFDictionaryCreateMutable,
                        %i[pointer long pointer pointer], :pointer
        attach_function :cf_dictionary_set_value, :CFDictionarySetValue, %i[pointer pointer pointer], :void
        attach_function :cf_set_get_count, :CFSetGetCount, [:pointer], :long
        attach_function :cf_set_get_values, :CFSetGetValues, %i[pointer pointer], :void

        attach_function :hid_manager_create, :IOHIDManagerCreate, %i[pointer uint32], :pointer
        attach_function :hid_manager_set_device_matching, :IOHIDManagerSetDeviceMatching, %i[pointer pointer], :void
        attach_function :hid_manager_copy_devices, :IOHIDManagerCopyDevices, [:pointer], :pointer
        attach_function :hid_device_get_property, :IOHIDDeviceGetProperty, %i[pointer pointer], :pointer
        # IOReturn is a signed 32-bit kern_return_t, so failures come back negative.
        attach_function :hid_device_open, :IOHIDDeviceOpen, %i[pointer uint32], :int
        attach_function :hid_device_close, :IOHIDDeviceClose, %i[pointer uint32], :int
        attach_function :hid_device_set_report, :IOHIDDeviceSetReport, %i[pointer int long buffer_in long], :int

        UTF8 = 0x08000100 # kCFStringEncodingUTF8
        SINT32 = 3 # kCFNumberSInt32Type
        private_constant :UTF8, :SINT32

        class << self
          # The address of a CoreFoundation global, such as a callbacks struct.
          #
          # @param name [String]
          # @return [FFI::Pointer]
          def global(name)
            ffi_libraries.each do |library|
              symbol = library.find_variable(name)
              return symbol if symbol
            end
            raise Error, "CoreFoundation has no #{name}"
          end

          # @param text [String]
          # @return [FFI::Pointer] a new CFString the caller must {release}
          def string(text)
            cf_string_create_with_c_string(nil, text, UTF8)
          end

          # @param value [Integer]
          # @return [FFI::Pointer] a new CFNumber the caller must {release}
          def number(value)
            buffer = FFI::MemoryPointer.new(:int32)
            buffer.write_int32(value)
            cf_number_create(nil, SINT32, buffer)
          end

          # Reads a borrowed CFString.
          #
          # @param ref [FFI::Pointer]
          # @return [String] "" when ref is not a CFString or cannot be converted
          def read_string(ref)
            return "" unless type?(ref, cf_string_get_type_id)

            size = cf_string_get_maximum_size_for_encoding(cf_string_get_length(ref), UTF8) + 1
            buffer = FFI::MemoryPointer.new(:char, size)
            return "" if cf_string_get_c_string(ref, buffer, size, UTF8).zero?

            buffer.read_string.force_encoding(Encoding::UTF_8)
          end

          # Reads a borrowed CFNumber.
          #
          # @param ref [FFI::Pointer]
          # @return [Integer] 0 when ref is not a CFNumber
          def read_integer(ref)
            return 0 unless type?(ref, cf_number_get_type_id)

            buffer = FFI::MemoryPointer.new(:int32)
            cf_number_get_value(ref, SINT32, buffer)
            buffer.read_int32
          end

          # Releases a CF object, ignoring nil and NULL.
          #
          # @param ref [FFI::Pointer, nil]
          # @return [void]
          def release(ref)
            cf_release(ref) unless ref.nil? || ref.null?
          end

          private

          def type?(ref, type_id)
            !ref.null? && cf_get_type_id(ref) == type_id
          end
        end
      end

      # IOReturn values, from IOKit/IOReturn.h.
      NO_DEVICE = 0xE00002C0
      NOT_PRIVILEGED = 0xE00002C1
      EXCLUSIVE_ACCESS = 0xE00002C5
      NOT_ATTACHED = 0xE00002D9
      NOT_PERMITTED = 0xE00002E2
      REPORT_TYPE_FEATURE = 2 # kIOHIDReportTypeFeature
      private_constant :NO_DEVICE, :NOT_PRIVILEGED, :EXCLUSIVE_ACCESS, :NOT_ATTACHED, :NOT_PERMITTED,
                       :REPORT_TYPE_FEATURE

      OPEN_REASONS = {
        BusyError => "it is in use by another program",
        PermissionError => "permission denied",
        NotFoundError => "it is no longer attached"
      }.freeze
      PROPERTY_KEYS = %w[VendorID ProductID VersionNumber Manufacturer Product SerialNumber].freeze
      private_constant :OPEN_REASONS, :PROPERTY_KEYS

      # Maps a failed IOHIDDeviceSetReport to the error a handle raises.
      #
      # @param code [Integer] the IOReturn, signed or unsigned
      # @return [Class] a {Blinkstick::Error} subclass
      def self.error_for(code)
        case code & 0xFFFF_FFFF
        when EXCLUSIVE_ACCESS then BusyError
        when NOT_PRIVILEGED, NOT_PERMITTED then PermissionError
        when NO_DEVICE, NOT_ATTACHED then DisconnectedError
        else TransferFailed
        end
      end

      # Maps a failed IOHIDDeviceOpen to the error {#open} raises.
      #
      # @param code [Integer] the IOReturn, signed or unsigned
      # @return [Class] a {Blinkstick::Error} subclass
      def self.open_error_for(code)
        case code & 0xFFFF_FFFF
        when EXCLUSIVE_ACCESS then BusyError
        when NOT_PRIVILEGED, NOT_PERMITTED then PermissionError
        when NO_DEVICE, NOT_ATTACHED then NotFoundError
        else Error
        end
      end

      # Formats an IOReturn for messages.
      #
      # @param code [Integer]
      # @return [String]
      def self.describe(code)
        format("IOReturn 0x%08X", code & 0xFFFF_FFFF)
      end

      # An open IOHIDDevice.
      class Handle
        # @param device [FFI::Pointer] an IOHIDDeviceRef retained for this handle, which
        #   releases it on {#close}
        # @param serial [String, nil] named in error messages
        def initialize(device, serial: nil)
          @device = device
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

          code = Native.hid_device_set_report(@device, REPORT_TYPE_FEATURE, report.getbyte(0), report,
                                              report.bytesize)
          return if code.zero?

          raise IOKit.error_for(code), "#{name}: writing a report failed (#{IOKit.describe(code)})"
        end

        # Closes the device, then releases the reference the handle owns.
        # Calling it again does nothing, and it never raises.
        #
        # @return [void]
        def close
          return if @closed

          @closed = true
          begin
            Native.hid_device_close(@device, OPEN_OPTIONS)
          ensure
            Native.release(@device)
          end
          nil
        end

        private

        def name
          @serial || "the stick"
        end
      end

      # @return [Array<Device>] every BlinkStick attached
      def list
        keys = PROPERTY_KEYS.to_h { |key| [key, Native.string(key)] }
        manager = Native.hid_manager_create(nil, OPEN_OPTIONS)
        raise Error, "IOKit could not create an IOHIDManager" if manager.null?

        match(manager, keys)
        copy_devices(manager).map { |ref| device_for(ref, keys) }
      ensure
        Native.release(manager)
        keys&.each_value { |key| Native.release(key) }
      end

      # Retains the device reference for the handle, so the handle never
      # depends on the listed {Device} staying alive. The retain is released
      # here if the open fails, and by {Handle#close} otherwise.
      #
      # @param device [Device] a device from {#list}
      # @return [Handle]
      # @raise [NotFoundError, PermissionError, BusyError] when it cannot be opened
      def open(device)
        ref = Native.cf_retain(device.id)
        code = Native.hid_device_open(ref, OPEN_OPTIONS)
        return handle = Handle.new(ref, serial: device.serial) if code.zero?

        error = IOKit.open_error_for(code)
        reason = OPEN_REASONS.fetch(error, "the OS refused")
        raise error, "Could not open #{device.serial}: #{reason} (#{IOKit.describe(code)})"
      ensure
        Native.release(ref) unless handle
      end

      private

      def match(manager, keys)
        dict = Native.cf_dictionary_create_mutable(nil, 2, Native.global("kCFTypeDictionaryKeyCallBacks"),
                                                   Native.global("kCFTypeDictionaryValueCallBacks"))
        { "VendorID" => VENDOR_ID, "ProductID" => PRODUCT_ID }.each do |key, id|
          Native.cf_dictionary_set_value(dict, keys.fetch(key), number = Native.number(id))
        ensure
          Native.release(number)
        end
        Native.hid_manager_set_device_matching(manager, dict)
      ensure
        Native.release(dict)
      end

      # Retains each device before the set that holds it is released.
      def copy_devices(manager)
        set = Native.hid_manager_copy_devices(manager)
        return [] if set.null?

        count = Native.cf_set_get_count(set)
        values = FFI::MemoryPointer.new(:pointer, count)
        Native.cf_set_get_values(set, values)
        values.read_array_of_pointer(count).map do |ref|
          FFI::AutoPointer.new(Native.cf_retain(ref), Native.method(:cf_release))
        end
      ensure
        Native.release(set)
      end

      # Properties are borrowed (the Get rule), so nothing read here is released.
      def device_for(ref, keys)
        property = ->(key) { Native.hid_device_get_property(ref, keys.fetch(key)) }
        Device.new(id: ref, serial: Native.read_string(property["SerialNumber"]),
                   manufacturer: Native.read_string(property["Manufacturer"]),
                   product: Native.read_string(property["Product"]),
                   release: Native.read_integer(property["VersionNumber"]))
      end
    end
  end
end
