# frozen_string_literal: true

module Cash
  # Idempotent on every dimension. `linked` reports only newly-linked rows;
  # previously linked ones are skipped silently.
  class Tracking
    Result = Struct.new(:wallet, :linked, keyword_init: true)

    DEFAULT_CURRENCY = "PLN"

    def self.enable!(...) = new(...).enable!

    def initialize(user:, currency: DEFAULT_CURRENCY)
      @user     = user
      @currency = currency
    end

    def enable!
      wallet = WalletResolver.call(user: @user, currency: @currency)
      linked = backfill_atm_withdrawals
      Result.new(wallet: wallet, linked: linked)
    end

    private

    def backfill_atm_withdrawals
      BankTransaction.for_user(@user)
                     .where(payment_method: "blik_atm", direction: "debit")
                     .find_each.count { |tx| AtmWithdrawalLinker.link!(tx) }
    end
  end
end
