# frozen_string_literal: true

module MerchantRules
  class Destroyer
    Result = Struct.new(:success?, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(rule:, actor:)
      @rule  = rule
      @actor = actor
    end

    def call
      @rule.destroy!
      ::Enrichment::TransactionEnricher.rebuild!(user: @actor)
      Result.new(success?: true)
    end
  end
end
