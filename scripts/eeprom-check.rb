#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual EEPROM check, run by the maintainer before a release, once per OS.
# It WRITES the EEPROM of a real stick (name, info block 2 and the LED mode),
# then puts everything back. Rake, CI and the gem never run it, and it is not
# shipped in the gem.
#
#   ruby -Ilib scripts/eeprom-check.rb SERIAL --yes-write-eeprom
#
# Exit status: 0 all checks passed and everything restored, 1 a mismatch or a
# failed restore, 2 refused (bad arguments, a serial that matches no stick or
# several, or a stick not in mode 2 or 3).

FLAG = "--yes-write-eeprom"
USAGE = "usage: ruby -Ilib scripts/eeprom-check.rb SERIAL #{FLAG}".freeze

# Checked before the gem or any backend is loaded, so a refused run never
# reaches a device.
def serial_from(args)
  serial = args.size == 2 && args.include?(FLAG) ? (args - [FLAG]).first : nil
  return serial if serial && !serial.empty? && !serial.start_with?("-")

  warn USAGE
  exit 2
end

SERIAL = serial_from(ARGV)

# Autoloads resolve through $LOAD_PATH, so put this tree's lib first, or an
# installed older gem's backend could load.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require_relative "../lib/blinkstick"

# Writes test values to one stick, reads each back and restores the originals.
class EepromCheck
  TEST_NAME = "eeprom-check"
  TEST_BLOCK2 = "eeprom-check-2"

  def initialize(stick, out: $stdout)
    @stick = stick
    @out = out
    @failures = 0
  end

  # @return [Integer] the exit status: 0, or 1 on any mismatch or failed restore
  def run
    save
    begin
      check_name
      check_block2
      check_mode
    ensure
      restore
    end
    finish
  end

  private

  def save
    @mode = @stick.mode
    refuse unless %i[ws2812 ws2812_mirror].include?(@mode)
    @block1 = @stick.info_block(1)
    @block2 = @stick.info_block(2)
    say "saved: name=#{@block1.inspect} block2=#{@block2.inspect} mode=#{@mode}"
  end

  def refuse
    warn "refused: mode is #{@mode.inspect}, and mode= cannot restore it (only 2 or 3 are settable)"
    exit 2
  end

  def check_name
    say "write: name=#{TEST_NAME.inspect}"
    @stick.name = TEST_NAME
    expect("name", TEST_NAME, @stick.name)
  end

  def check_block2
    say "write: block 2=#{TEST_BLOCK2.inspect}"
    @stick.write_info_block(2, TEST_BLOCK2)
    expect("block 2", TEST_BLOCK2.b, @stick.info_block(2))
  end

  def check_mode
    # The other mode first, so both writes really happen.
    other = @mode == :ws2812 ? :ws2812_mirror : :ws2812
    [other, @mode].each do |mode|
      say "write: mode=#{mode}"
      @stick.mode = mode
      expect("mode", mode, @stick.mode)
    end
  end

  # Runs every step even on Ctrl-C: INT is noted, not acted on, until done.
  def restore
    interrupted = false
    previous = trap("INT") { interrupted = true }
    restore_all
    return unless interrupted

    fail_with "restore: interrupted (Ctrl-C), but every restore step still ran"
  ensure
    trap("INT", previous) if previous
  end

  def restore_all
    attempt("block 1") { @stick.write_info_block(1, @block1) }
    attempt("block 2") { @stick.write_info_block(2, @block2) }
    attempt("mode") { @stick.mode = @mode }
    expect_restored
  end

  def attempt(label)
    yield
    say "restore: #{label} written"
  rescue StandardError => e
    fail_with "restore: #{label} failed: #{e.class}: #{e.message}"
  end

  def expect_restored
    reads = { "restored block 1" => [@block1, -> { @stick.info_block(1) }],
              "restored block 2" => [@block2, -> { @stick.info_block(2) }],
              "restored mode" => [@mode, -> { @stick.mode }] }
    reads.each do |label, (wanted, read)|
      expect(label, wanted, read.call)
    rescue StandardError => e
      fail_with "restore: #{label} read back failed: #{e.class}: #{e.message}"
    end
  end

  def expect(label, wanted, got)
    if wanted == got
      say "read: #{label} ok (#{got.inspect})"
    else
      fail_with "read: #{label} MISMATCH, wanted #{wanted.inspect}, got #{got.inspect}"
    end
  end

  def fail_with(message)
    @failures += 1
    warn message
  end

  def say(message)
    @out.puts message
  end

  def finish
    say(@failures.zero? ? "eeprom-check: all checks passed" : "eeprom-check: #{@failures} failure(s)")
    @failures.zero? ? 0 : 1
  end
end

# One stick only: open(serial:) takes the first of several that share a serial.
def require_unique(serial)
  count = Blinkstick.list.count { |info| info.serial == serial }
  return if count == 1

  if count.zero?
    warn "refused: no stick with serial #{serial.inspect} found"
  else
    warn "refused: #{count} sticks share serial #{serial.inspect}, so it is ambiguous"
  end
  exit 2
end

stick = nil
begin
  require_unique(SERIAL)
  stick = Blinkstick.open(serial: SERIAL)
  exit EepromCheck.new(stick).run
rescue Blinkstick::Error => e
  warn "eeprom-check: #{e.class}: #{e.message}"
  exit 1
ensure
  stick&.close
end
