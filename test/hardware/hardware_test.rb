# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require "timeout"

# Drives real sticks. Skipped unless BLINKSTICK_HARDWARE=1, which `rake
# hardware` sets. These tests use the real backend, never a fake, and write
# colours only: nothing here touches the stick's EEPROM.
class HardwareTest < Minitest::Test
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
    skip "shared open is a macOS check (hidraw has no equivalent)" unless RbConfig::CONFIG["host_os"].include?("darwin")
    info = supported_sticks.first
    skip "no supported BlinkStick attached" unless info

    results = shared_open(info.serial)

    results.each_with_index do |(status, err), i|
      assert_predicate status, :success?, "child #{i} failed (shared open of #{info.serial}): #{err}"
    end
  end

  private

  def supported_sticks
    Blinkstick.list.select { |info| info.model.supported? }
  end

  def together(nano, square)
    sticks = []
    sticks << Blinkstick.open(serial: nano.serial)
    sticks << Blinkstick.open(serial: square.serial)
    sticks.zip(%i[green blue]) { |stick, colour| stick.colour = colour }
    sleep 0.3
  ensure
    sticks&.each { |stick| turn_off_and_close(stick) }
  end

  def turn_off_and_close(stick)
    stick.off
  ensure
    stick.close
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

  # A Ruby process holding a stick open. Stdout and stderr stay separate, and
  # every wait has a timeout so a hung child cannot hang rake.
  class Child
    def initialize(args)
      @stdin, @stdout, @stderr, @wait = Open3.popen3(RbConfig.ruby, "-I#{LIB}", "-e", CHILD, *args)
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
