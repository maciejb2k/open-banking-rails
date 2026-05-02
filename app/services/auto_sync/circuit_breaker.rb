# frozen_string_literal: true

module AutoSync
  # Observes a finalized scheduled OperationRun and bumps the related
  # SyncSchedule's consecutive_failures counter. After FAILURE_THRESHOLD
  # consecutive non-success runs, paused_until is set so the dispatcher
  # stops picking the schedule up for COOLDOWN. A successful run resets
  # both counter and pause.
  #
  # Called explicitly from TransactionSyncJob (and any future scheduled
  # job) — never from an AR callback. Per AGENTS.md: side-effects belong
  # to the service that triggered the save, not to model lifecycle hooks.
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

    # Only BankConnection-scoped scheduled runs map to a schedule today.
    # User- or BankAccount-scoped runs aren't part of slice 1's auto-sync.
    def schedule_for(run)
      return nil unless run.subject.is_a?(BankConnection)
      run.subject.sync_schedule
    end
  end
end
