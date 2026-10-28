# frozen_string_literal: true

module Blinkstick
  # A cooperative cancellation token for effects ({Stick#blink} and friends).
  #
  # Every pause in an effect is {#wait}, so {#cancel} wakes it at once. It
  # uses only Mutex and ConditionVariable (no Thread#raise, Thread#kill or
  # Timeout), so it is safe across threads and works under a fiber scheduler.
  # One token may be shared by several effects. Do not call any of its
  # methods from a signal trap handler; see {#cancel}.
  #
  #   cancel = Blinkstick::Cancellation.new
  #   Thread.new { sleep 10; cancel.cancel }
  class Cancellation
    # The longest single condition wait, in seconds. ConditionVariable#wait
    # raises RangeError for very long timeouts, so a longer pause is made of
    # several waits (the loop works out what remains each time).
    LONGEST_WAIT = 86_400
    private_constant :LONGEST_WAIT

    def initialize
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @cancelled = false
    end

    # Cancels the token and wakes every waiter. Safe to call again.
    #
    # Do not call this from a signal trap handler: Mutex#synchronize raises
    # ThreadError there. Set a flag in the trap and cancel from a thread that
    # watches it.
    #
    # @return [nil]
    # @raise [ThreadError] when called from a signal trap handler
    def cancel
      @mutex.synchronize do
        @cancelled = true
        @condition.broadcast
      end
      nil
    end

    # @return [Boolean] true once {#cancel} has been called
    def cancelled?
      @mutex.synchronize { @cancelled }
    end

    # Pauses for +seconds+, or until the token is cancelled, whichever is first.
    #
    # @param seconds [Numeric] a finite number, 0 or more
    # @return [Boolean] true if cancelled (at once if it already was), false
    #   once +seconds+ have passed
    # @raise [ArgumentError] when +seconds+ is not a finite Numeric of 0 or more
    def wait(seconds)
      check_seconds(seconds)
      deadline = now + seconds
      @mutex.synchronize do
        until @cancelled
          remaining = deadline - now
          break if remaining <= 0

          @condition.wait(@mutex, [remaining, LONGEST_WAIT].min)
        end
        @cancelled
      end
    end

    private

    def check_seconds(seconds)
      ok = seconds.is_a?(Numeric) && seconds.real? && seconds.to_f.finite? && seconds >= 0
      raise ArgumentError, "seconds must be a finite number of 0 or more, got #{seconds.inspect}" unless ok
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
