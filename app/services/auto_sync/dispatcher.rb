# frozen_string_literal: true

module AutoSync
  # Polled every minute by AutoSync::DispatcherJob (sidekiq-cron). Scans
  # SyncSchedule.due, creates a scheduled OperationRun per due schedule,
  # enqueues TransactionSyncJob, and advances next_run_at via NextRunCalculator.
  #
  # Idempotency rests on the partial unique index on operation_runs
  # (subject_type, subject_id, kind, scheduled_for). If two ticks overlap and
  # both try to dispatch the same slot, one wins, the other catches
  # RecordNotUnique and skips — no double-fire, no double-advance.
  class Dispatcher
    # How long to pause a schedule whose connection isn't authorized. Long
    # enough to stop minute-by-minute re-examination, short enough that a
    # re-authorization is picked up the same day.
    REVOKED_BACKOFF = 6.hours

    Result = Struct.new(:examined, :dispatched, :skipped, keyword_init: true) do
      def to_log_hash = { examined: examined, dispatched: dispatched, skipped: skipped }
    end

    def self.call(...) = new(...).call

    def initialize(now: Time.current)
      @now = now
    end

    def call
      examined = 0
      dispatched = 0
      skipped = 0

      due_schedules.find_each do |schedule|
        examined += 1
        if dispatch(schedule)
          dispatched += 1
        else
          skipped += 1
        end
      end

      Result.new(examined: examined, dispatched: dispatched, skipped: skipped)
    end

    private

    def due_schedules
      SyncSchedule.due.includes(bank_connection: { tpp_credential: :user })
    end

    def dispatch(schedule)
      connection = schedule.bank_connection
      user = connection.tpp_credential&.user

      # Connection no longer authorized (revoked / expired / closed) or
      # orphaned. Pause for REVOKED_BACKOFF instead of just skipping — without
      # the pause, the dispatcher re-examines this row every minute (1440×/day)
      # for nothing. The pause is a soft sleep, not a circuit-breaker trip:
      # we don't bump consecutive_failures (no actual run happened), and the
      # user can re-authorize and click "Resume" to clear it sooner.
      unless connection.status == "authorized" && user.present?
        schedule.update!(paused_until: REVOKED_BACKOFF.from_now)
        return false
      end

      slot = schedule.next_run_at || @now
      run_id = nil

      ActiveRecord::Base.transaction do
        run = OperationRun.create!(
          kind: TransactionSyncJob::KIND,
          trigger: "scheduled",
          subject: connection,
          triggered_by_user: user,
          scheduled_for: slot,
          params: {}
        )
        run_id = run.id

        schedule.update!(
          next_run_at: NextRunCalculator.call(
            input: next_run_input(schedule, user),
            last_dispatched_at: @now
          ),
          last_dispatched_at: @now
        )
      end

      TransactionSyncJob.perform_later(run_id)
      true
    rescue ActiveRecord::RecordNotUnique
      # Another tick already dispatched this exact slot. Safe to skip.
      false
    end

    def next_run_input(schedule, user)
      NextRunCalculator::Input.new(
        cadence: schedule.cadence,
        preferred_hour: schedule.preferred_hour,
        timezone: user_timezone(user),
        from: @now
      )
    end

    def user_timezone(user)
      user.respond_to?(:timezone) ? (user.timezone.presence || "UTC") : "UTC"
    end
  end
end
