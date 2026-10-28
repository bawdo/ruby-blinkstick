# frozen_string_literal: true

# Builds a FakeBackend whose sticks carry names, for the name tests.
module NamedSticks
  include FakeBackend::Installer

  DEVICES = {
    "BS000001-3.0" => FakeBackend.nano("BS000001-3.0"),
    "BS000002-3.1" => FakeBackend.square("BS000002-3.1"),
    "BS000004-3.0" => FakeBackend.nano("BS000004-3.0")
  }.freeze

  # @param names [Hash{String => String}] serial to the name stored on it
  def named_backend(names)
    backend = install_backend(FakeBackend.new(*DEVICES.values_at(*names.keys)))
    names.each { |serial, name| backend.store(serial, info_blocks: { 1 => name.b, 2 => "".b }) }
    backend
  end

  # @return [Array<Boolean>] closed? for every handle the backend opened
  def closed_states(backend)
    backend.handles.map(&:closed?)
  end
end
