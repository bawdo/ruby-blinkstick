# frozen_string_literal: true

module Blinkstick
  class Stick
    # Blink, pulse and morph, ported from go-blinkstick's effects.go. Each
    # blocks the calling thread (no thread is spawned), pauses with
    # <tt>cancel.wait(seconds)</tt> so a {Cancellation} cuts it short, and
    # takes the Stick's lock per transfer, not for the whole effect.
    #
    # Two effects running on one stick at once interleave their frames; that
    # is documented, not prevented. A cancelled effect returns false and
    # leaves the LEDs as they are.
    module Effects
      # Seconds between morph steps.
      STEP = 0.02

      # STEP in integer nanoseconds, for counting steps as Go does.
      STEP_NS = (STEP * 1_000_000_000).round
      private_constant :STEP, :STEP_NS

      # Flashes every LED on and off, ending off.
      #
      # @param colour [Colour, String, Symbol, Array<Integer>] anything {Colour.parse} takes
      # @param period [Numeric] seconds per flash, finite and above 0 (half on, half off)
      # @param repeats [Integer] how many flashes, 1 or more
      # @param cancel [#cancelled?, #wait, nil] a {Cancellation} (or anything with
      #   its two methods); nil makes pauses plain timed waits
      # @return [Boolean] true when it ran to the end, false when cancelled
      # @raise [InvalidColourError] before anything is sent, when colour is not a colour
      # @raise [ArgumentError] before anything is sent, when period or repeats is out of range
      # @raise [ClosedError] after {#close}
      # @raise [BusyError] when another program holds the stick mid-transfer
      # @raise [PermissionError] when the system refuses access mid-transfer
      # @raise [DisconnectedError] when the stick stops responding and reconnecting to it fails
      def blink(colour, period:, repeats: 1, cancel: nil)
        target = Colour.parse(colour)
        check_time(:period, period, positive: true)
        check_repeats(repeats)
        cancel ||= Cancellation.new
        half = period / 2.0
        repeats.times.all? do
          beat(cancel, half) { self.colour = target } && beat(cancel, half) { off }
        end
      end

      # Fades every LED up to a colour and back down, starting and ending off.
      #
      # @param colour [Colour, String, Symbol, Array<Integer>] anything {Colour.parse} takes
      # @param duration [Numeric] seconds per pulse, finite and above 0 (half up, half down)
      # @param repeats [Integer] how many pulses, 1 or more
      # @param cancel [#cancelled?, #wait, nil] a {Cancellation} (or anything with
      #   its two methods); nil makes pauses plain timed waits
      # @return [Boolean] true when it ran to the end, false when cancelled
      # @raise [InvalidColourError] before anything is sent, when colour is not a colour
      # @raise [ArgumentError] before anything is sent, when duration or repeats is out of range
      # @raise [ClosedError] after {#close}
      # @raise [BusyError] when another program holds the stick mid-transfer
      # @raise [PermissionError] when the system refuses access mid-transfer
      # @raise [DisconnectedError] when the stick stops responding and reconnecting to it fails
      def pulse(colour, duration:, repeats: 1, cancel: nil)
        target = Colour.parse(colour)
        check_time(:duration, duration, positive: true)
        check_repeats(repeats)
        cancel ||= Cancellation.new
        half = duration / 2.0
        repeats.times.all? do
          beat(cancel, 0) { off } && fade(target, half, cancel) && fade(Colour::OFF, half, cancel)
        end
      end

      # Fades every LED from what the stick shows now to a colour, in 20 ms
      # steps. The colour is brightness limited once, so a fade to full red at
      # a limit of 128 ends at 128, not 64. A duration under one step jumps
      # straight to the colour.
      #
      # @param colour [Colour, String, Symbol, Array<Integer>] anything {Colour.parse} takes
      # @param duration [Numeric] seconds, finite and 0 or more
      # @param cancel [#cancelled?, #wait, nil] a {Cancellation} (or anything with
      #   its two methods); nil makes pauses plain timed waits
      # @return [Boolean] true when it ran to the end, false when cancelled
      # @raise [InvalidColourError] before anything is sent, when colour is not a colour
      # @raise [ArgumentError] before anything is sent, when duration is out of range
      # @raise [ClosedError] after {#close}
      # @raise [BusyError] when another program holds the stick mid-transfer
      # @raise [PermissionError] when the system refuses access mid-transfer
      # @raise [DisconnectedError] when the stick stops responding and reconnecting to it fails
      def morph(colour, duration:, cancel: nil)
        target = Colour.parse(colour)
        check_time(:duration, duration, positive: false)
        fade(target, duration, cancel || Cancellation.new)
      end

      private

      # Fades from the stick's frame to target; see {#morph}.
      def fade(target, duration, cancel)
        return false if cancel.cancelled?

        from = frame
        to = brightness_scaled(target)
        # Integer nanoseconds as Go does: 0.58 s is 29 steps, where float division gives 28.
        steps = [(duration * 1_000_000_000).round / STEP_NS, 1].max
        (1..steps).all? do |step|
          next false if cancel.cancelled?

          write_frame(from.map { |start| lerp(start, to, step, steps) }, scale: false)
          step == steps || !cancel.wait(STEP)
        end
      end

      # Runs one write then pauses (a pause of 0 is skipped). Returns truthy
      # to keep going; nil when cancelled before the write, false when the
      # pause was cancelled.
      def beat(cancel, seconds)
        return if cancel.cancelled?

        yield
        !(seconds.positive? && cancel.wait(seconds))
      end

      # The colour step/steps of the way from one colour to another.
      def lerp(from, target, step, steps)
        Colour.new(red: towards(from.red, target.red, step, steps),
                   green: towards(from.green, target.green, step, steps),
                   blue: towards(from.blue, target.blue, step, steps))
      end

      # One channel: a + (b - a) * step / steps, truncating towards zero as Go
      # does (Integer#/ would floor).
      def towards(from, target, step, steps)
        delta = (target - from) * step
        from + (delta.negative? ? -(-delta / steps) : delta / steps)
      end

      def check_time(name, seconds, positive:)
        ok = seconds.is_a?(Numeric) && seconds.real? && seconds.to_f.finite? &&
             (positive ? seconds.positive? : seconds >= 0)
        return if ok

        bound = positive ? "above 0" : "of 0 or more"
        raise ArgumentError, "#{name} must be a finite number #{bound}, got #{seconds.inspect}"
      end

      def check_repeats(repeats)
        return if repeats.is_a?(Integer) && repeats >= 1

        raise ArgumentError, "repeats must be an Integer of 1 or more, got #{repeats.inspect}"
      end
    end
  end
end
