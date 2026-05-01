# frozen_string_literal: true

module Cash
  # Builds a ManualTransaction + its enrichment in a single DB transaction.
  # The cash wallet for (user, currency) is resolved (or created) on the fly,
  # so callers don't need to know about wallets at all.
  #
  # The enrichment is always written with source: "manual" — that's the whole
  # point of cash entries, the user is the authority. If a category was
  # picked, category_overridden goes to true so the rebuild path treats it
  # as untouchable. If only a merchant was picked, the effective category
  # falls back to merchant.default_category at read time.
  class TransactionCreator
    # Explicit boundary between the controller (raw form params) and the
    # service. Carries every attribute the creator can consume; helper
    # methods normalize/parse values that arrive as strings from a form
    # but as Date / Integer from internal callers.
    Input = Struct.new(
      :amount, :currency, :direction, :booking_date, :transaction_date,
      :title, :note, :counterparty_name, :merchant_id, :category_id,
      :payment_method,
      keyword_init: true
    ) do
      def normalized_currency
        currency.to_s.strip.upcase.presence || "PLN"
      end

      def normalized_direction      = direction.presence || "debit"
      def normalized_payment_method = payment_method.presence || "cash"

      # Parses the form-supplied amount string ("12,50") into integer cents
      # under the given currency. Returns nil for blank input — the caller
      # passes that straight through and lets model validation surface a
      # presence error. ArgumentError from BigDecimal collapses to nil for
      # the same reason.
      def amount_cents_in(currency_iso)
        raw = amount.to_s.strip.tr(",", ".")
        return nil if raw.blank?
        Money.from_amount(BigDecimal(raw), currency_iso).cents
      rescue ArgumentError
        nil
      end

      def parsed_booking_date     = parse_date(booking_date) || Date.current
      def parsed_transaction_date = parse_date(transaction_date)

      private

      def parse_date(value)
        return nil if value.blank?
        value.is_a?(Date) ? value : Date.parse(value.to_s)
      rescue Date::Error
        nil
      end
    end

    Result = Struct.new(:success?, :transaction, :enrichment, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(user:, input:)
      @user  = user
      @input = input
    end

    def call
      currency = @input.normalized_currency
      wallet   = WalletResolver.call(user: @user, currency: currency)

      ActiveRecord::Base.transaction do
        payment_method    = @input.normalized_payment_method
        counterparty_name = @input.counterparty_name.presence

        tx = ManualTransaction.new(
          bank_account:      wallet,
          amount_cents:      @input.amount_cents_in(currency),
          currency:          currency,
          direction:         @input.normalized_direction,
          status:            "booked",
          booking_date:      @input.parsed_booking_date,
          transaction_date:  @input.parsed_transaction_date,
          title:             @input.title.presence,
          note:              @input.note.presence,
          counterparty_name: counterparty_name,
          payment_method:    payment_method,
          counterparty_kind: Banking::CounterpartyResolver.call(
            payment_method:    payment_method,
            counterparty_iban: nil,
            counterparty_name: counterparty_name,
            user:              @user
          ),
          source:            "manual",
          created_by_user:   @user
        )
        tx.save!

        enrichment = tx.build_enrichment(
          merchant:            resolve_merchant,
          category:            resolve_category,
          source:              "manual",
          category_overridden: @input.category_id.present?,
          enriched_at:         Time.current
        )
        enrichment.save!

        return Result.new(success?: true, transaction: tx, enrichment: enrichment)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, transaction: e.record, error_messages: e.record.errors.full_messages)
    rescue ArgumentError => e
      Result.new(success?: false, transaction: nil, error_messages: [ e.message ])
    end

    private

    def resolve_merchant
      return nil if @input.merchant_id.blank?
      @user.merchants.active.find_by(id: @input.merchant_id)
    end

    def resolve_category
      return nil if @input.category_id.blank?
      @user.categories.active.find_by(id: @input.category_id)
    end
  end
end
