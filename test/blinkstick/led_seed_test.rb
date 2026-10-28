# frozen_string_literal: true

require "test_helper"

# The read that seeds the last frame on the first single LED write.
class LedSeedTest < Minitest::Test
  include FakeBackend::Installer

  RED = Blinkstick::Colour.new(red: 255, green: 0, blue: 0)

  SERIAL = "BS000001-3.0"

  def teardown
    @stick&.close
    super
  end

  def test_seeding_read_retries
    stick = open_stick(fail_reads: 2)

    stick[0] = :red

    assert_equal [Blinkstick::Report.led(0, RED)], handle.writes
    assert_equal({ 6 => 1 }, handle.reads_by_id)
  end

  # The seeding read fails on the first handle and again after reopening.
  def test_failed_seeding_read_raises_without_writing
    stick = open_stick(fail_reads: 3)
    @backend.next_open(SERIAL, fail_reads: 3)

    assert_raises(Blinkstick::DisconnectedError) { stick[0] = :red }
    assert_equal [[], []], @backend.handles.map(&:writes)
  end

  # Nothing was written, so reopening repaints nothing; the new handle seeds.
  def test_failed_seeding_read_reconnects_and_seeds
    stick = open_stick(fail_reads: 3)

    stick[0] = :red

    assert_equal [Blinkstick::Report.led(0, RED)], @backend.handles.last.writes
    assert_equal({ 6 => 1 }, @backend.handles.last.reads_by_id)
  end

  def test_failed_seeding_read_is_retried_on_the_next_write
    stick = open_stick(fail_reads: 3)
    @backend.next_open(SERIAL, fail_reads: 3)
    assert_raises(Blinkstick::DisconnectedError) { stick[0] = :red }

    stick[0] = :red

    assert_equal 2, @backend.handles.size
    assert_equal({ 6 => 1 }, @backend.handles.last.reads_by_id)
  end

  private

  def open_stick(**)
    @backend = install_backend(FakeBackend.new(FakeBackend.nano, **))
    @stick = Blinkstick.open
  end

  def handle
    @backend.handles.fetch(0)
  end
end
