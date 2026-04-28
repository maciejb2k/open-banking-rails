class CreateBankConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_connections do |t|
      t.references :tpp_credential, null: false, foreign_key: true
      t.references :replaces, foreign_key: { to_table: :bank_connections }

      t.string :bank_slug, null: false
      t.string :bank_country, default: "PL"
      t.string :bank_name        # human-readable (cache from /aspsps)

      t.string :status, null: false, default: "pending"
      t.string :psu_type, default: "personal"

      # Encrypted at app layer
      t.text :session_id
      t.text :psu_id_hash
      t.text :raw_session_payload   # full POST /sessions response, source of truth

      t.boolean :access_balances, null: false, default: true
      t.boolean :access_transactions, null: false, default: true

      t.datetime :authorized_at
      t.datetime :valid_until
      t.datetime :last_refreshed_at
      t.datetime :last_synced_at
      t.datetime :closed_at

      t.text :last_error

      t.timestamps
    end

    add_index :bank_connections, :status
    add_index :bank_connections, :valid_until
    add_index :bank_connections, [ :tpp_credential_id, :bank_slug, :status ],
                                 name: "index_bank_connections_lookup"
  end
end
