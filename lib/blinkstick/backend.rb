# frozen_string_literal: true

require "rbconfig"

module Blinkstick
  # Finds and opens sticks through the operating system. One backend exists
  # per OS; it is chosen and loaded on the first {Blinkstick.list} or
  # {Blinkstick.open}, never by `require "blinkstick"`.
  #
  # A backend responds to `#list`, returning an Array of {Device}, and
  # `#open(device)`, returning a handle. A handle responds to
  # `#write_feature(report)`, where report is a binary String whose first
  # byte is the report ID; to `#read_feature(report_id, size)`, returning a
  # binary String whose first byte is the report ID and whose length is the
  # number of bytes the OS returned (size includes the ID byte); and to
  # `#close`, which may be called more than once. Handles raise
  # {Blinkstick::Error} subclasses, or {TransferFailed} for a failure worth
  # trying again, from either transfer.
  #
  # @api private
  module Backend
    # How many times a transfer is tried before the stick counts as gone.
    ATTEMPTS = 3

    # Raised by a handle when a transfer failed but may work if tried again.
    class TransferFailed < Error; end

    # A stick as the OS reports it. The id is opaque outside the backend
    # that listed it (a path on Linux, an IOKit reference on macOS) and the
    # serial is always a String.
    Device = Data.define(:id, :serial, :manufacturer, :product, :release)

    class << self
      # Replaces the backend, for tests.
      attr_writer :current

      # @return [#list, #open] the backend for the running OS, loaded once
      # @raise [Blinkstick::Error] when the OS has no backend
      def current
        @current ||= for_host(RbConfig::CONFIG["host_os"])
      end

      private

      def for_host(host_os)
        case host_os
        when /darwin/
          require_relative "backend/iokit"
          IOKit.new
        when /linux/
          require_relative "backend/hidraw"
          Hidraw.new
        else
          raise Error, "unsupported platform: #{host_os}"
        end
      end
    end
  end
end
