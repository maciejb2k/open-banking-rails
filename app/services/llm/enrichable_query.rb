# frozen_string_literal: true

module Llm
  # NON_MERCHANT_PAYMENT_METHODS are kinds where "merchant" is a category
  # error (BLIK p2p is people, ATM is cash, internal transfers/topups are own
  # accounts, fees are bank charges). counterparty_kind: "self" filters
  # own-account moves - set at sync time by Banking::CounterpartyResolver.
  class EnrichableQuery
    NON_MERCHANT_PAYMENT_METHODS = %w[blik_p2p blik_atm internal_transfer topup fee].freeze

    def self.scope(user:)         = new(user).scope
    def self.groups(user:, scope: nil) = new(user).groups(scope: scope)

    def initialize(user)
      @user = user
    end

    # The numeric-title regex drops BLIK codes / reference numbers - pure
    # digits are not merchant signal.
    def scope
      BankTransaction.for_user(@user)
        .joins(:enrichment)
        .merge(TransactionEnrichment.merchantless)
        .where("(title IS NOT NULL AND title <> '' AND title !~ '^[0-9]+$') OR (counterparty_name IS NOT NULL AND counterparty_name <> '')")
        .where.not(payment_method: NON_MERCHANT_PAYMENT_METHODS)
        .where.not(counterparty_kind: "self")
    end

    # Skip groups already covered by an existing MerchantRule (any source/state)
    # - sending them again would yield the same suggestion and waste tokens.
    def groups(scope: nil)
      relation = scope || self.scope
      rules    = @user.merchant_rules.to_a

      relation.find_each.each_with_object({}) do |tx, acc|
        key = [ Enrichment::TitleNormalizer.call(tx.title), tx.counterparty_name.to_s ]
        next if key == [ "", "" ]
        next if covered_by_existing_rule?(rules, tx)
        acc[key] ||= { title: tx.title, counterparty_name: tx.counterparty_name }
      end
    end

    private

    def covered_by_existing_rule?(rules, tx)
      rules.any? do |r|
        value = case r.field
        when "title"             then tx.title
        when "counterparty_name" then tx.counterparty_name
        when "counterparty_iban" then tx.counterparty_iban
        end
        value.present? && r.matches?(value)
      end
    end
  end
end
