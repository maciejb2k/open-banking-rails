# frozen_string_literal: true

module AutoSync
  # After FAILURE_THRESHOLD consecutive non-success scheduled runs, paused_until
  # is set so the dispatcher stops picking the schedule up for COOLDOWN.
  class CircuitBreaker
    COOLDOWN = 24.hours

    def self.observe(...) = new(...).observe

    def initialize(run:)
      @run = run
    end

    def observe
      return unless @run.trigger == "scheduled"
      return unless @run.terminal?

      schedule = schedule_for(@run)
      return if schedule.nil?

      if @run.status == "succeeded"
        reset!(schedule)
      else
        bump_failure!(schedule)
      end
    end

    private

    def reset!(schedule)
      return if schedule.consecutive_failures.zero? && schedule.paused_until.nil?
      schedule.update!(consecutive_failures: 0, paused_until: nil)
    end

    def bump_failure!(schedule)
      new_count = schedule.consecutive_failures + 1
      attrs = { consecutive_failures: new_count }
      attrs[:paused_until] = COOLDOWN.from_now if new_count >= SyncSchedule::FAILURE_THRESHOLD
      schedule.update!(attrs)
    end

    def schedule_for(run)
      return nil unless run.subject.is_a?(BankConnection)
      run.subject.sync_schedule
    end
  end
end
