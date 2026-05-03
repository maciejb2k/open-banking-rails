class RequireTriggeredByUserOnOperationRuns < ActiveRecord::Migration[8.1]
  def up
    # Verified empty at migration-write time, but check defensively - a
    # background job between this commit and `db:migrate` could insert a
    # row with a NULL user, and `change_column_null false` would fail.
    if OperationRun.where(triggered_by_user_id: nil).exists?
      raise "Refusing to migrate: orphan OperationRuns without triggered_by_user_id exist. Backfill or delete them first."
    end

    change_column_null :operation_runs, :triggered_by_user_id, false
  end

  def down
    change_column_null :operation_runs, :triggered_by_user_id, true
  end
end
