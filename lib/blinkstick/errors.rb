# frozen_string_literal: true

module Blinkstick
  # Base class for every error this gem raises on purpose.
  class Error < StandardError; end

  # Raised when no BlinkStick matches the requested serial or index.
  class NotFoundError < Error; end

  # Raised when another program has seized the stick (macOS only).
  class BusyError < Error; end

  # Raised when the operating system refuses access to the device.
  class PermissionError < Error; end

  # Raised when opening a stick whose model is not recognised.
  class UnsupportedModelError < Error; end

  # Raised when using a device after it has been closed.
  class ClosedError < Error; end

  # Raised when the stick is unplugged or stops responding mid-use.
  class DisconnectedError < Error; end

  # Raised when more than one attached stick has the requested name.
  class DuplicateNameError < Error; end

  # Raised when a value cannot be turned into a {Colour}.
  class InvalidColourError < ArgumentError; end
end
