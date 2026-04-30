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
    Result = Struct.new(:success?, :transaction, :enrichment, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(user:, params:)
      @user   = user
      @params = params
    end

    def call
      currency = normalized_currency
      wallet   = WalletResolver.call(user: @user, currency: currency)

      ActiveRecord::Base.transaction do
        tx = ManualTransaction.new(
          bank_account:      wallet,
          amount_cents:      parsed_amount_cents(currency),
          currency:          currency,
          direction:         @params[:direction].presence || "debit",
          status:            "booked",
          booking_date:      parsed_date(@params[:booking_date]) || Date.current,
          transaction_date:  parsed_date(@params[:transaction_date]),
          title:             @params[:title].presence,
          note:              @params[:note].presence,
          counterparty_name: @params[:counterparty_name].presence,
          payment_method:    @params[:payment_method].presence || "cash",
          source:            "manual",
          created_by_user:   @user
        )
        tx.save!

        enrichment = tx.build_enrichment(
          merchant:            resolve_merchant,
          category:            resolve_category,
          source:              "manual",
          category_overridden: @params[:category_id].present?,
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

    def normalized_currency
      raw = @params[:currency].to_s.strip.upcase
      raw.presence || "PLN"
    end

    def parsed_amount_cents(currency)
      raw = @params[:amount].to_s.strip.tr(",", ".")
      return nil if raw.blank?
      Money.from_amount(BigDecimal(raw), currency).cents
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
      @user.merchants.active.find_by(id: @params[:merchant_id])
    end

    def resolve_category
      return nil if @params[:category_id].blank?
      @user.categories.active.find_by(id: @params[:category_id])
    end
  end
end
