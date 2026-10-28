# frozen_string_literal: true

require "test_helper"

class CancellationTest < Minitest::Test
  def setup
    @token = Blinkstick::Cancellation.new
  end

  def test_starts_uncancelled
    refute_predicate @token, :cancelled?
  end

  def test_wait_times_out_false
    started = monotonic
    result = @token.wait(0.05)
    elapsed = monotonic - started

    refute result
    assert_operator elapsed, :>=, 0.05
    assert_operator elapsed, :<, 2
  end

  def test_wait_zero_returns_false_at_once
    refute @token.wait(0)
  end

  def test_wait_after_cancel_is_immediate
    assert_nil @token.cancel
    started = monotonic

    assert @token.wait(5)
    assert_operator monotonic - started, :<, 1
  end

  # The cancel is sent only once the waiter is blocked in wait, so this
  # proves a cancel wakes a wait already asleep.
  def test_cancel_from_another_thread_wakes_wait
    waiter = Thread.new { @token.wait(5) }
    await_sleeping(waiter)
    started = monotonic
    @token.cancel

    assert waiter.value
    assert_operator monotonic - started, :<, 1
  ensure
    waiter&.kill
  end

  # ConditionVariable#wait raises RangeError past about 1e18 seconds, so a
  # huge but finite wait must still be woken by a cancel.
  def test_huge_wait_is_woken_by_cancel
    canceller = Thread.new do
      sleep 0.05
      @token.cancel
    end

    assert @token.wait(1e19)
  ensure
    canceller&.join
  end

  def test_cancel_wakes_every_waiter
    waiters = Array.new(3) { Thread.new { @token.wait(5) } }
    sleep 0.05
    @token.cancel

    assert_equal [true, true, true], waiters.map(&:value)
  end

  def test_cancel_is_idempotent
    assert_nil @token.cancel
    assert_nil @token.cancel
    assert_predicate @token, :cancelled?
  end

  def test_bad_seconds
    [-1, -0.1, Float::NAN, Float::INFINITY, nil, "1", :a].each do |bad|
      assert_raises(ArgumentError, "expected ArgumentError for #{bad.inspect}") { @token.wait(bad) }
    end
  end

  private

  # Polls until the thread is asleep, for at most two seconds.
  def await_sleeping(thread)
    deadline = monotonic + 2
    Thread.pass until thread.status == "sleep" || monotonic > deadline

    assert_equal "sleep", thread.status, "the waiter never blocked"
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
