# frozen_string_literal: true

module Cash
  # Activates cash tracking for a user: creates the per-currency wallet
  # (default PLN) and back-links every historical BLIK ATM withdrawal so
  # the user's first dashboard view after toggling the feature already
  # reflects their existing cash flows.
  #
  # Idempotent on every dimension:
  #   - Wallet is find-or-create (Cash::WalletResolver).
  #   - Each ATM withdrawal links at most once (DB-enforced via the
  #     unique partial index on linked_bank_transaction_id).
  # Re-running on the same user is safe — `linked` will report only newly
  # linked rows; previously linked ones are skipped silently.
  #
  # The User#track_cash flag is the caller's responsibility — this service
  # only materializes the side effects of "tracking is now on". Toggling
  # tracking off is a separate concern (data preservation, undo policy)
  # and lives elsewhere if/when needed.
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

    # Walk every historical BLIK ATM debit on the user's synced accounts
    # and feed it through the linker. Returns the count of newly-linked
    # rows; previously-linked or ineligible rows fall through as nil
    # (linker is the authority on eligibility).
    def backfill_atm_withdrawals
      BankTransaction.for_user(@user)
                     .where(payment_method: "blik_atm", direction: "debit")
                     .find_each.count { |tx| AtmWithdrawalLinker.link!(tx) }
    end
  end
end
