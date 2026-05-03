class AllowManualBankAccounts < ActiveRecord::Migration[8.1]
  # Cash wallets are bank_accounts that aren't backed by a TPP connection.
  # Owned directly by a user, no IBAN, currency-scoped. The check constraint
  # is the source of truth - exactly one of (tpp_credential_id, manual_owner_id)
  # must be set, in lockstep with the `manual` flag. AR validations mirror it
  # so the failure mode is a clean message instead of a constraint violation.
  def change
    add_column :bank_accounts, :manual, :boolean, null: false, default: false
    add_reference :bank_accounts, :manual_owner,
                  foreign_key: { to_table: :users }, null: true

    change_column_null :bank_accounts, :tpp_credential_id, true

    add_index :bank_accounts, :manual

    add_check_constraint :bank_accounts,
      "(manual = true  AND tpp_credential_id IS NULL     AND manual_owner_id IS NOT NULL) OR " \
      "(manual = false AND tpp_credential_id IS NOT NULL AND manual_owner_id IS NULL)",
      name: "bank_accounts_ownership_xor"
  end
end
