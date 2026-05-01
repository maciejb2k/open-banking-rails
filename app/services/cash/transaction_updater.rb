# frozen_string_literal: true

module Cash
  # Edit an existing manual cash entry. Only manually-sourced rows are
  # editable here; atm-link rows are produced by the ATM linker (Phase 3)
  # and shouldn't be free-edited from this UI — the caller decides whether
  # to surface the edit affordance at all.
  #
  # Currency is locked: changing it would mean moving the row to a different
  # wallet, which is destructive (balance jumps in two places). If the user
  # really wants that, they delete + re-add.
  class TransactionUpdater
    Result = Struct.new(:success?, :transaction, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(transaction:, params:)
      @transaction = transaction
      @params      = params
    end

    def call
      ActiveRecord::Base.transaction do
        payment_method    = @params[:payment_method].presence || @transaction.payment_method
        counterparty_name = @params[:counterparty_name]

        @transaction.assign_attributes(
          amount_cents:      parsed_amount_cents,
          direction:         @params[:direction].presence || @transaction.direction,
          booking_date:      parsed_date(@params[:booking_date]) || @transaction.booking_date,
          transaction_date:  parsed_date(@params[:transaction_date]),
          title:             @params[:title],
          note:              @params[:note],
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
          category_overridden: @params[:category_id].present?,
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

    def parsed_amount_cents
      raw = @params[:amount].to_s.strip.tr(",", ".")
      return @transaction.amount_cents if raw.blank?
      Money.from_amount(BigDecimal(raw), @transaction.currency).cents
    rescue ArgumentError
      nil
    end

    def parsed_date(value)
      return nil if value.blank?
      value.is_a?(Date) ? value : Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    def resolve_merchant
      return nil if @params[:merchant_id].blank?
      transaction_user.merchants.active.find_by(id: @params[:merchant_id])
    end

    def resolve_category
      return nil if @params[:category_id].blank?
      transaction_user.categories.active.find_by(id: @params[:category_id])
    end

    # Cash wallets are owned via manual_owner_id; resolve back to constrain
    # merchant/category lookups to the row's owner.
    def transaction_user
      @transaction_user ||= User.find(@transaction.bank_account.manual_owner_id)
    end
  end
end
