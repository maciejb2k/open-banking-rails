class CreateBankAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_accounts do |t|
      t.references :tpp_credential, null: false, foreign_key: true
      t.references :current_bank_connection, foreign_key: { to_table: :bank_connections }

      # Enable Banking UID - UUID, stable across session renewals
      t.string :uid, null: false

      # Primary identification
      t.string :iban
      t.string :bban
      t.jsonb :all_account_ids, null: false, default: []

      # Account properties (snapshot from /sessions; refined by /accounts/{uid}/details)
      t.string :currency
      t.string :name                # holder name (sometimes empty for PKO)
      t.string :product             # bank's product name
      t.string :details             # secondary description (PKO uses this)
      t.string :cash_account_type   # CACC / CARD / CASH / LOAN / OTHR / SVGS
      t.string :usage               # PRIV / COMM
      t.string :status, null: false, default: "active"  # active | inactive | revoked

      # Servicer (BIC, bank name) - only some banks return this
      t.jsonb :account_servicer

      # Source-of-truth payloads
      t.jsonb :raw_account_resource    # what came in /sessions response
      t.jsonb :raw_details             # what came from /accounts/{uid}/details (if fetched)
      t.datetime :details_fetched_at

      # Sync state - for future Data module
      t.datetime :balances_synced_at
      t.datetime :transactions_synced_at

      t.timestamps
    end

    add_index :bank_accounts, :uid, unique: true
    add_index :bank_accounts, :iban
    add_index :bank_accounts, :status
  end
end
