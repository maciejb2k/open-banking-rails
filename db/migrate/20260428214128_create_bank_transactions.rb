class CreateBankTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_transactions do |t|
      t.references :bank_account, null: false, foreign_key: true

      # Per-bank stable identifier (transaction_id || entry_reference).
      # Revolut: entry_reference (UUID-like) — transaction_id is always null.
      # PKO/mBank: transaction_id (= base64 of entry_reference).
      # See docs/banks/comparison.md in PoC repo.
      t.string :external_id, null: false

      # Normalized columns (sourced from raw_payload, see TransactionNormalizer).
      t.date :booking_date,     null: false
      t.date :value_date
      t.date :transaction_date

      # Money pattern: amount in minor units (cents/grosze), currency is the
      # ISO 4217 code that determines the subunit scale. Always read together
      # via `monetize :amount_cents, with_model_currency: :currency`.
      # bigint chosen so a single transaction can represent values up to
      # ~92 quadrillion minor units — safe for any realistic bank entry.
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, limit: 3

      t.string :direction, null: false                  # "credit" | "debit"
      t.string :status, null: false, default: "booked"  # "booked" | "pending"

      t.text   :title              # remittance_information[0]
      t.string :type_hint          # remittance_information[1] — bank-specific raw

      t.string :counterparty_name
      t.string :counterparty_iban         # for mBank, derived from BBAN ("PL" + identification)

      t.string :bank_transaction_code     # Berlin Group code; only Revolut populates

      # Source of truth (encrypted at app layer, jsonb-as-string).
      t.text :raw_payload, null: false

      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :bank_transactions, %i[bank_account_id external_id], unique: true
    add_index :bank_transactions, %i[bank_account_id booking_date]
    add_index :bank_transactions, :status
  end
end
