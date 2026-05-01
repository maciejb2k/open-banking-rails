class AddCounterpartyKindToLedgerRows < ActiveRecord::Migration[8.1]
  # Persisted identity of the other side of a ledger entry: "self" (between
  # the user's own accounts), "external" (to/from a third party), or
  # "unknown" (no IBAN and no counterparty name to decide from). Set once
  # at sync/create time by Banking::CounterpartyResolver so enrichment,
  # analytics, and the ledger_entries view share one source of truth.
  def change
    add_column :bank_transactions,   :counterparty_kind, :string, null: false, default: "unknown"
    add_column :manual_transactions, :counterparty_kind, :string, null: false, default: "unknown"

    add_index :bank_transactions,   :counterparty_kind
    add_index :manual_transactions, :counterparty_kind
  end
end
