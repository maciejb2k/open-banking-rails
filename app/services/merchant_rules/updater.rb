# frozen_string_literal: true

module MerchantRules
  class Updater
    Result = Struct.new(:success?, :rule, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(rule:, actor:, attributes:)
      @rule       = rule
      @actor      = actor
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      if @rule.update(@attributes)
        ::Enrichment::TransactionEnricher.rebuild!(user: @actor)
        Result.new(success?: true, rule: @rule)
      else
        Result.new(success?: false, rule: @rule, error_messages: @rule.errors.full_messages)
      end
    end
  end
end
