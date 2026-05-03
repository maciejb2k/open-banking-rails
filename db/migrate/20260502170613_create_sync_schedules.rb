class CreateSyncSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_schedules do |t|
      # One schedule per BankConnection. Per-connection (not per-user) because
      # rate limits are per-bank - different banks need different cadences.
      t.references :bank_connection, null: false, foreign_key: true,
                                     index: { unique: true }

      # Preset list, validated in the model. Adding a new cadence is a code
      # change, not a migration - keeps NextRunCalculator the source of truth.
      t.string  :cadence,        null: false, default: "daily"

      # 0..23 in the user's local timezone. Slot computation lives in
      # AutoSync::NextRunCalculator.
      t.integer :preferred_hour, null: false, default: 8

      # Opt-in. New schedules start disabled until the user turns auto-sync on.
      t.boolean :enabled,        null: false, default: false

      # Materialized - recomputed after every dispatch. Indexed below for the
      # dispatcher's `due` scan.
      t.datetime :next_run_at
      t.datetime :last_dispatched_at

      # Circuit breaker - set when consecutive_failures crosses the threshold.
      # While set, the schedule is excluded from `due` until this time passes.
      t.datetime :paused_until
      t.integer  :consecutive_failures, null: false, default: 0

      t.timestamps
    end

    # Partial index - only enabled schedules participate in the dispatcher scan.
    add_index :sync_schedules, %i[enabled next_run_at],
              where: "enabled = true",
              name: "index_sync_schedules_due"

    # Idempotency for scheduled dispatches: if two ticks overlap, the second
    # OperationRun.create! for the same (subject, kind, scheduled_for) raises
    # RecordNotUnique and the dispatcher swallows it. Manual runs leave
    # scheduled_for NULL and are excluded by the partial WHERE.
    add_column :operation_runs, :scheduled_for, :datetime
    add_index  :operation_runs, %i[subject_type subject_id kind scheduled_for],
               unique: true,
               where: "scheduled_for IS NOT NULL",
               name: "index_operation_runs_scheduled_for_idempotency"
  end
end
