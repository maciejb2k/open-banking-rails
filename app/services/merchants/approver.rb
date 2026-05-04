# frozen_string_literal: true

module Merchants
  class Approver
    Result = Struct.new(:success?, :merchant, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(merchant:, actor:)
      @merchant = merchant
      @actor    = actor
    end

    def call
      ActiveRecord::Base.transaction do
        @merchant.update!(approved_at: Time.current, approved_by: @actor)
        @merchant.merchant_rules.where(source: "llm", enabled: false).each do |rule|
          rule.update!(enabled: true, approved_at: Time.current, approved_by: @actor)
        end
      end
      ::Enrichment::TransactionEnricher.rebuild!(user: @merchant.user)
      Result.new(success?: true, merchant: @merchant)
    end
  end
end
