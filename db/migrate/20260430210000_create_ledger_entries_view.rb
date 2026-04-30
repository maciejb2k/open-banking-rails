class CreateLedgerEntriesView < ActiveRecord::Migration[8.1]
  def change
    create_view :ledger_entries
  end
end
