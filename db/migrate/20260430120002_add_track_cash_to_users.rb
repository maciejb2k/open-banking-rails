class AddTrackCashToUsers < ActiveRecord::Migration[8.1]
  # Opt-in for cash tracking. Off by default so existing users keep current
  # blik_atm classification (kategoria "Wypłaty z bankomatu" jako expense)
  # until they explicitly enable it. Phase 3 reads this to decide whether
  # ATM withdrawals get linked to a cash wallet.
  def change
    add_column :users, :track_cash, :boolean, null: false, default: false
  end
end
