# frozen_string_literal: true

module Cash
  # One wallet per (user, currency) - balances stay native (no implicit FX).
  # uid is namespaced "cash_<user_id>_<currency>" so it never collides with
  # bank UIDs from Enable Banking.
  class WalletResolver
    def self.call(user:, currency: "PLN")
      new(user: user, currency: currency).call
    end

    def initialize(user:, currency:)
      @user = user
      @currency = currency.to_s.upcase
    end

    def call
      raise ArgumentError, "user required" if @user.nil?
      raise ArgumentError, "currency required" if @currency.blank?

      BankAccount.find_or_create_by!(uid: wallet_uid) do |wallet|
        wallet.manual            = true
        wallet.manual_owner      = @user
        wallet.tpp_credential    = nil
        wallet.currency          = @currency
        wallet.cash_account_type = "CASH"
        wallet.status            = "active"
        wallet.name              = wallet_name
        wallet.all_account_ids   = []
      end
    end

    private

    def wallet_uid
      "cash_#{@user.id}_#{@currency.downcase}"
    end

    def wallet_name
      "Cash wallet (#{@currency})"
    end
  end
end
