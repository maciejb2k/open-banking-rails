class UpdateLedgerEntriesToVersion4 < ActiveRecord::Migration[8.1]
  def change
    update_view :ledger_entries, version: 4, revert_to_version: 3

    remove_index :transaction_enrichments, :recurring, where: "(recurring = true)"
    remove_column :transaction_enrichments, :recurrence_interval, :string
    remove_column :transaction_enrichments, :recurring, :boolean, default: false, null: false
  end
end
