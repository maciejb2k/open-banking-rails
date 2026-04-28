class AddRawBalancesToBankAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :bank_accounts, :raw_balances, :text  # encrypted (jsonb-as-string)
  end
end
