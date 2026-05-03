# frozen_string_literal: true

module AutoSync
  # Idempotency rests on the partial unique index on operation_runs
  # (subject_type, subject_id, kind, scheduled_for). Overlapping ticks racing
  # the same slot fall through RecordNotUnique - no double-fire.
  class Dispatcher
    # Stops minute-by-minute re-examination of an unauthorized connection but
    # picks up re-authorization the same day.
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

      # Soft sleep (not a circuit-breaker trip - no consecutive_failures bump,
      # since no actual run happened). User can re-authorize to clear it sooner.
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
