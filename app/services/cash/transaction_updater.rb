# frozen_string_literal: true

module Cash
  # Edit an existing manual cash entry. Only manually-sourced rows are
  # editable here; atm-link rows are produced by the ATM linker (Phase 3)
  # and shouldn't be free-edited from this UI — the caller decides whether
  # to surface the edit affordance at all.
  #
  # Currency is locked: changing it would mean moving the row to a different
  # wallet, which is destructive (balance jumps in two places). If the user
  # really wants that, they delete + re-add. So Input has no `currency` —
  # the row's existing currency drives amount parsing.
  class TransactionUpdater
    # Update semantics differ from creation: blank `title`/`note`/
    # `counterparty_name` are passed through as-is so the user can
    # explicitly clear a field. Blank `direction` / `payment_method` /
    # `booking_date` mean "keep what's there" — those have no
    # null-meaningful value on a saved row.
    Input = Struct.new(
      :amount, :direction, :booking_date, :transaction_date,
      :title, :note, :counterparty_name, :merchant_id, :category_id,
      :payment_method,
      keyword_init: true
    ) do
      def amount_cents_in(currency_iso, fallback:)
        raw = amount.to_s.strip.tr(",", ".")
        return fallback if raw.blank?
        Money.from_amount(BigDecimal(raw), currency_iso).cents
      rescue ArgumentError
        nil
      end

      def parsed_booking_date(fallback:) = parse_date(booking_date) || fallback
      def parsed_transaction_date        = parse_date(transaction_date)

      private

      def parse_date(value)
        return nil if value.blank?
        value.is_a?(Date) ? value : Date.parse(value.to_s)
      rescue Date::Error
        nil
      end
    end

    Result = Struct.new(:success?, :transaction, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(transaction:, input:)
      @transaction = transaction
      @input       = input
    end

    def call
      ActiveRecord::Base.transaction do
        payment_method    = @input.payment_method.presence || @transaction.payment_method
        counterparty_name = @input.counterparty_name

        @transaction.assign_attributes(
          amount_cents:      @input.amount_cents_in(@transaction.currency, fallback: @transaction.amount_cents),
          direction:         @input.direction.presence || @transaction.direction,
          booking_date:      @input.parsed_booking_date(fallback: @transaction.booking_date),
          transaction_date:  @input.parsed_transaction_date,
          title:             @input.title,
          note:              @input.note,
          counterparty_name: counterparty_name,
          payment_method:    payment_method,
          counterparty_kind: Banking::CounterpartyResolver.call(
            payment_method:    payment_method,
            counterparty_iban: nil,
            counterparty_name: counterparty_name,
            user:              transaction_user
          )
        )
        @transaction.save!

        enrichment = @transaction.enrichment || @transaction.build_enrichment(source: "manual")
        enrichment.assign_attributes(
          merchant:            resolve_merchant,
          category:            resolve_category,
          source:              "manual",
          category_overridden: @input.category_id.present?,
          enriched_at:         Time.current
        )
        enrichment.save!

        return Result.new(success?: true, transaction: @transaction)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, transaction: e.record, error_messages: e.record.errors.full_messages)
    rescue ArgumentError => e
      Result.new(success?: false, transaction: @transaction, error_messages: [ e.message ])
    end

    private

    def resolve_merchant
      return nil if @input.merchant_id.blank?
      transaction_user.merchants.active.find_by(id: @input.merchant_id)
    end

    def resolve_category
      return nil if @input.category_id.blank?
      transaction_user.categories.active.find_by(id: @input.category_id)
    end

    # Cash wallets are owned via manual_owner_id; resolve back to constrain
    # merchant/category lookups to the row's owner.
    def transaction_user
      @transaction_user ||= User.find(@transaction.bank_account.manual_owner_id)
    end
  end
end
