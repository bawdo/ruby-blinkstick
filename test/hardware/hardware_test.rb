# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require "timeout"

# Shared by the hardware test classes: the child process plumbing and the
# helpers that find sticks and put them away.
module HardwareSupport
  LIB = File.expand_path("../../lib", __dir__)

  # Each child holds the stick open until the parent says go, so both are
  # open at once when they write.
  CHILD = <<~RUBY
    require "blinkstick"
    stick = Blinkstick.open(serial: ARGV.fetch(0))
    begin
      puts "READY"
      $stdout.flush
      $stdin.gets
      stick.colour = ARGV.fetch(1).to_sym
      stick.off
    ensure
      stick.close
    end
  RUBY

  FRAME_CHILD = <<~RUBY
    require "blinkstick"
    stick = Blinkstick.open(serial: ARGV.fetch(0))
    begin
      stick.frame = ARGV.drop(1)
      puts "READY"
      $stdout.flush
      $stdin.gets
      stick.off
    ensure
      stick.close
    end
  RUBY

  # Distinct colours, so a frame read back shows which LED holds which.
  PALETTE = %w[red green blue yellow cyan magenta white orange].freeze

  private

  def supported_sticks
    Blinkstick.list.select { |info| info.model.supported? }
  end

  def macos?
    RbConfig::CONFIG["host_os"].include?("darwin")
  end

  def turn_off_and_close(stick)
    stick.off
  ensure
    stick.close
  end

  # Opens each supported stick in turn, yielding it, and puts it away
  # afterwards. Inverse and the brightness limit are reset first, so the
  # final off is sent as plain zeros, not flipped to full white.
  def each_stick
    sticks = supported_sticks
    skip "no supported BlinkStick attached" if sticks.empty?

    sticks.each do |info|
      stick = Blinkstick.open(serial: info.serial)
      begin
        yield stick
      ensure
        reset_and_put_away(stick)
      end
    end
  end

  def reset_and_put_away(stick)
    stick.inverse = false
    stick.brightness_limit = 255
  ensure
    turn_off_and_close(stick)
  end

  # A Ruby process holding a stick open. Stdout and stderr stay separate, and
  # every wait has a timeout so a hung child cannot hang rake.
  class Child
    def initialize(args, script = CHILD)
      @stdin, @stdout, @stderr, @wait = Open3.popen3(RbConfig.ruby, "-I#{LIB}", "-e", script, *args)
      @err = +""
      @reader = Thread.new { @err << @stderr.read }
    end

    def await_ready(seconds)
      unless @stdout.wait_readable(seconds)
        @reader.join(5)
        raise "child never printed READY: #{@err}"
      end

      line = @stdout.gets
      return if line == "READY\n"

      @reader.join(5)
      raise "child sent #{line.inspect} instead of READY: #{@err}"
    end

    def release
      @stdin.puts
      @stdin.close
    end

    # @return [Array(Process::Status, String)] exit status and stderr
    def finish(seconds)
      raise Timeout::Error, "child did not exit within #{seconds}s" unless @wait.join(seconds)

      @reader.join(5)
      [@wait.value, @err]
    end

    def kill
      Process.kill("KILL", @wait.pid) if @wait.alive?
    rescue Errno::ESRCH
      nil
    ensure
      [@stdin, @stdout, @stderr].each { |io| io.close unless io.closed? }
    end
  end
end

# Drives real sticks. Skipped unless BLINKSTICK_HARDWARE=1, which `rake
# hardware` sets. These tests use the real backend, never a fake, and write
# colours only: nothing here touches the stick's EEPROM.
class HardwareTest < Minitest::Test
  include HardwareSupport

  def setup
    return if ENV["BLINKSTICK_HARDWARE"] == "1"

    skip "set BLINKSTICK_HARDWARE=1 (or run `rake hardware`) to drive real sticks"
  end

  def test_list_finds_a_supported_stick
    supported = Blinkstick.list.select { |info| info.model.supported? }

    refute_empty supported, "no supported BlinkStick attached"
  end

  def test_open_by_serial_sets_red_then_off
    info = supported_sticks.first
    skip "no supported BlinkStick attached" unless info

    Blinkstick.open(serial: info.serial) do |stick|
      assert_equal info, stick.info
      stick.colour = :red
      sleep 0.3
    ensure
      stick.off
    end
  end

  def test_nano_and_square_together
    nano = supported_sticks.find { |info| info.model == Blinkstick::Model::NANO }
    square = supported_sticks.find { |info| info.model == Blinkstick::Model::SQUARE }
    skip "needs a Nano and a Square attached together" unless nano && square

    together(nano, square)
  end

  def test_two_processes_share_one_open_stick_on_macos
    skip "shared open is a macOS check (hidraw has no equivalent)" unless macos?
    info = supported_sticks.first
    skip "no supported BlinkStick attached" unless info

    results = shared_open(info.serial)

    results.each_with_index do |(status, err), i|
      assert_predicate status, :success?, "child #{i} failed (shared open of #{info.serial}): #{err}"
    end
  end

  private

  def together(nano, square)
    sticks = []
    sticks << Blinkstick.open(serial: nano.serial)
    sticks << Blinkstick.open(serial: square.serial)
    sticks.zip(%i[green blue]) { |stick, colour| stick.colour = colour }
    sleep 0.3
  ensure
    sticks&.each { |stick| turn_off_and_close(stick) }
  end

  # Both children are READY (open) before either is released to write.
  def shared_open(serial)
    children = [[serial, "red"], [serial, "blue"]].map { |args| Child.new(args) }
    children.each { |child| child.await_ready(30) }
    children.each(&:release)
    children.map { |child| child.finish(30) }
  ensure
    children&.each(&:kill)
  end
end

# Reads and writes LEDs, the mode and the info blocks of every attached
# stick. Writes colours only: reports 2, 3 and 4 are never written.
class HardwareLedTest < Minitest::Test
  include HardwareSupport

  def setup
    return if ENV["BLINKSTICK_HARDWARE"] == "1"

    skip "set BLINKSTICK_HARDWARE=1 (or run `rake hardware`) to drive real sticks"
  end

  def test_frame_reads_back_what_was_written
    each_stick do |stick|
      colours = PALETTE.take(stick.info.model.leds).map { |name| Blinkstick::Colour.parse(name) }
      stick.frame = colours

      assert_equal colours, stick.frame, "frame read back differs on #{stick.info.serial}"
    end
  end

  def test_setting_one_led_changes_only_that_led
    each_stick do |stick|
      base = Array.new(stick.info.model.leds) { Blinkstick::Colour.parse(:blue) }

      base.each_index { |i| assert_only_led_changed(stick, base, i) }
    end
  end

  def test_mode_is_ws2812
    each_stick { |stick| assert_equal :ws2812, stick.mode, "mode of #{stick.info.serial}" }
  end

  def test_info_blocks_are_short_strings
    each_stick do |stick|
      [1, 2].each do |number|
        block = stick.info_block(number)

        assert_kind_of String, block
        assert_operator block.bytesize, :<=, 32, "info block #{number} of #{stick.info.serial}"
      end
    end
  end

  def test_second_process_reads_the_frame_the_first_wrote_on_macos
    skip "shared read is a macOS check (hidraw has no equivalent)" unless macos?
    info = supported_sticks.first
    skip "no supported BlinkStick attached" unless info

    names = PALETTE.take(info.model.leds)
    shared_read(info.serial, names)
  end

  private

  def assert_only_led_changed(stick, base, index)
    red = Blinkstick::Colour.parse(:red)
    stick.frame = base
    stick[index] = red

    assert_equal base.dup.tap { |expected| expected[index] = red }, stick.frame, "LED #{index} on #{stick.info.serial}"
    assert_equal red, stick[index]
  end

  # The child writes the frame and holds the stick open; the parent opens its
  # own handle on the same serial before the child is released, so both are
  # open at once, then reads the frame the child wrote.
  def shared_read(serial, names)
    child = Child.new([serial, *names], FRAME_CHILD)
    child.await_ready(30)
    read_while_child_holds(serial, names) { child.release }
    status, err = child.finish(30)

    assert_predicate status, :success?, "child failed (shared read of #{serial}): #{err}"
  ensure
    child&.kill
    switch_off(serial)
  end

  # Releases the child and puts the parent's own handle away on every path,
  # turning the stick off before closing it.
  def read_while_child_holds(serial, names, &)
    stick = Blinkstick.open(serial: serial)

    assert_equal names.map { |name| Blinkstick::Colour.parse(name) }, stick.frame, "shared read of #{serial}"
  ensure
    release_and_put_away(stick, &)
  end

  def release_and_put_away(stick)
    yield
  ensure
    turn_off_and_close(stick) if stick
  end

  # A last resort after a failed or killed child, which may have left the
  # stick lit. Best effort: it must not hide the failure that got us here.
  def switch_off(serial)
    Blinkstick.open(serial: serial, &:off)
  rescue Blinkstick::Error
    nil
  end
end

# The 0.3.0 features against a real stick: brightness limit, inverse,
# effects, names in the listing and the USB release. Colours only: reports
# 2, 3 and 4 (name, info blocks, mode) are never written.
class HardwareFeatureTest < Minitest::Test
  include HardwareSupport

  BLACK = Blinkstick::Colour.parse(:black)

  def setup
    return if ENV["BLINKSTICK_HARDWARE"] == "1"

    skip "set BLINKSTICK_HARDWARE=1 (or run `rake hardware`) to drive real sticks"
  end

  def test_brightness_limit_reads_back_scaled
    each_stick do |stick|
      stick.brightness_limit = 128
      stick.colour = :white

      assert_equal [Blinkstick::Colour.new(red: 128, green: 128, blue: 128)] * leds(stick), stick.frame
    end
  end

  def test_inverse_reads_back_as_written
    each_stick do |stick|
      colours = PALETTE.take(leds(stick)).map { |name| Blinkstick::Colour.parse(name) }
      stick.inverse = true
      stick.frame = colours

      assert_equal colours, stick.frame
      assert_equal colours.map(&:inverse), plain_frame(stick.info.serial), "a plain Stick reads the flipped bytes"
    end
  end

  def test_morph_ends_on_colour
    each_stick do |stick|
      assert stick.morph(:blue, duration: 0.2)
      assert_equal [Blinkstick::Colour.parse(:blue)] * leds(stick), stick.frame
    end
  end

  def test_blink_and_pulse_end_off
    each_stick do |stick|
      assert_ends_off(stick) { stick.blink(:red, period: 0.2, repeats: 2) }
      assert_ends_off(stick) { stick.pulse(:green, duration: 0.3) }
    end
  end

  def test_pre_cancelled_effect_changes_nothing
    each_stick do |stick|
      cancel = Blinkstick::Cancellation.new
      cancel.cancel
      stick.colour = :blue
      before = stick.frame

      assert_equal [false] * 3, cancelled_effects(stick, cancel)
      assert_equal before, stick.frame
    end
  end

  def test_list_with_names
    plain = Blinkstick.list.map(&:serial)
    named = Blinkstick.list(names: true)

    assert_equal plain.sort, named.map { |entry| entry.info.serial }.sort
    named.each { |entry| assert_kind_of Blinkstick::NamedInfo, entry }
  end

  def test_release_matches_model
    releases = { Blinkstick::Model::NANO => 0x0202, Blinkstick::Model::SQUARE => 0x0201 }
    sticks = supported_sticks
    skip "no supported BlinkStick attached" if sticks.empty?

    sticks.each { |info| assert_equal releases.fetch(info.model), info.release, "release of #{info.serial}" }
  end

  private

  def leds(stick)
    stick.info.model.leds
  end

  # The effect ran to the end (returned true) and left every LED off.
  def assert_ends_off(stick)
    assert yield
    assert_equal [BLACK] * leds(stick), stick.frame
  end

  # What each effect returned when run with a cancellation already raised.
  def cancelled_effects(stick, cancel)
    [stick.blink(:red, period: 0.2, cancel: cancel),
     stick.pulse(:red, duration: 0.2, cancel: cancel),
     stick.morph(:red, duration: 0.2, cancel: cancel)]
  end

  # A second, plain Stick on the same serial, which neither flips nor scales.
  def plain_frame(serial)
    Blinkstick.open(serial: serial, &:frame)
  end
end
