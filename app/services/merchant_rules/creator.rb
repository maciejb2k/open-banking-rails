# frozen_string_literal: true

module MerchantRules
  class Creator
    Result = Struct.new(:success?, :rule, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(merchant:, actor:, attributes:)
      @merchant   = merchant
      @actor      = actor
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      rule = @merchant.merchant_rules.build(@attributes.merge(
        user:        @actor,
        source:      "user",
        approved_at: Time.current,
        approved_by: @actor
      ))

      if rule.save
        ::Enrichment::TransactionEnricher.rebuild!(user: @actor)
        Result.new(success?: true, rule: rule)
      else
        Result.new(success?: false, rule: rule, error_messages: rule.errors.full_messages)
      end
    end
  end
end
