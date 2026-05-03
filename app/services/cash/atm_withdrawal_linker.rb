# frozen_string_literal: true

module Cash
  # The pair represents a location change of money, not a spend - both rows
  # live under category `transfers` and drop out of spend analytics.
  # Idempotent (DB-enforced via unique partial index on
  # linked_bank_transaction_id). Gated by User#track_cash.
  class AtmWithdrawalLinker
    ELIGIBLE_PAYMENT_METHODS = %w[blik_atm].freeze

    def self.link!(bank_transaction)
      new(bank_transaction).link!
    end

    def initialize(bank_transaction)
      @bank_tx = bank_transaction
    end

    def link!
      return nil unless eligible?
      return nil if already_linked?

      user = @bank_tx.user
      return nil unless user&.track_cash?

      wallet = WalletResolver.call(user: user, currency: @bank_tx.currency)

      ManualTransaction.transaction do
        topup = ManualTransaction.create!(
          bank_account:            wallet,
          amount_cents:            @bank_tx.amount_cents,
          currency:                @bank_tx.currency,
          direction:               "credit",
          status:                  "booked",
          booking_date:            @bank_tx.booking_date,
          transaction_date:        @bank_tx.transaction_date,
          title:                   topup_title,
          counterparty_name:       @bank_tx.counterparty_name,
          payment_method:          "cash_atm_topup",
          source:                  "atm_link",
          linked_bank_transaction: @bank_tx,
          created_by_user:         user
        )
        # The enricher would do this on the next sweep, but we want it
        # consistent immediately.
        topup.build_enrichment(
          source:      "system_fallback",
          category:    user.categories.find_by(slug: "cash_atm_topup"),
          enriched_at: Time.current
        ).save!
        topup
      end
    rescue ActiveRecord::RecordNotUnique
      # Race: another job linked the same bank tx - idempotent success.
      nil
    end

    private

    def eligible?
      ELIGIBLE_PAYMENT_METHODS.include?(@bank_tx.payment_method) &&
        @bank_tx.direction == "debit"
    end

    def already_linked?
      ManualTransaction.exists?(linked_bank_transaction_id: @bank_tx.id)
    end

    def topup_title
      bank_label = @bank_tx.bank_account.current_bank_connection&.bank_name.presence ||
                   @bank_tx.bank_account.tpp_credential&.name.presence ||
                   "Bank"
      "ATM withdrawal (#{bank_label})"
    end
  end
end
