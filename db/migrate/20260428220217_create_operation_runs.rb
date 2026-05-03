class CreateOperationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :operation_runs do |t|
      # What kind of operation. Free-form by design - we don't constrain at the DB
      # so new operation kinds can be added without a migration. Validated in the
      # model against OperationRun::KINDS.
      t.string :kind, null: false

      # Lifecycle: queued → running → succeeded | partial | failed
      t.string :status, null: false, default: "queued"

      # What the operation acts on. Polymorphic so a single table covers
      # user-wide / connection-scoped / account-scoped operations.
      # nil is allowed for system-level ops in the future.
      t.references :subject, polymorphic: true, null: true

      # Who kicked it off (nil = scheduled by cron / system).
      t.references :triggered_by_user, foreign_key: { to_table: :users }, null: true

      # manual | scheduled - distinguishes user click vs cron
      t.string :trigger, null: false, default: "manual"

      # Inputs to the operation (e.g. {date_from:, date_to:} for sync).
      t.jsonb :params, null: false, default: {}

      # Per-kind structured result (e.g. {accounts: [{bank_account_id:, inserted:, skipped:, error:}]}).
      # Schema-less by design - kind owns the contract.
      t.jsonb :summary, null: false, default: {}

      # Error message when status = failed (or last error from a partial run).
      t.text :error

      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :operation_runs, :kind
    add_index :operation_runs, :status
    add_index :operation_runs, :created_at
    add_index :operation_runs, %i[kind status]
  end
end
