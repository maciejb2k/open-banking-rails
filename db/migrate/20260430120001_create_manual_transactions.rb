class CreateManualTransactions < ActiveRecord::Migration[8.1]
  # Cash / off-bank ledger entries. Same enrichment pipeline as BankTransaction
  # via polymorphic transaction_enrichments - the LedgerEntry concern keeps the
  # interface uniform.
  #
  # No external_id and no uniqueness scope: the user is the source of truth, so
  # duplicate rows are a UX problem (warn + dedupe by hand), not a data problem.
  # `linked_bank_transaction_id` is the back-edge for ATM-withdrawal cash topups
  # (Phase 3) - unique partial index guarantees one cash entry per bank withdrawal.
  def change
    create_table :manual_transactions do |t|
      t.references :bank_account, null: false, foreign_key: true

      # Money pattern: same shape as BankTransaction (bigint cents + ISO 4217).
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, limit: 3

      t.string :direction, null: false                  # "credit" | "debit"
      t.string :status,    null: false, default: "booked"  # "booked" | "pending"

      t.date :booking_date, null: false
      t.date :transaction_date

      t.text   :title
      t.text   :note
      t.string :counterparty_name

      # cash | cash_atm_topup | cash_deposit | cash_fx_conversion | cash_adjustment
      t.string :payment_method

      # Provenance: manual = user typed it; atm_link = auto-generated from a
      # BLIK ATM withdrawal (Phase 3); csv_import / recurring reserved.
      t.string :source, null: false, default: "manual"

      t.references :linked_bank_transaction,
                   foreign_key: { to_table: :bank_transactions }, null: true
      t.references :created_by_user,
                   null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :manual_transactions, %i[bank_account_id booking_date]
    add_index :manual_transactions, :payment_method
    add_index :manual_transactions, :status
    add_index :manual_transactions, :linked_bank_transaction_id,
              unique: true,
              where: "linked_bank_transaction_id IS NOT NULL",
              name: "idx_manual_transactions_one_per_linked_bank_tx"
  end
end
