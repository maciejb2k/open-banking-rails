# frozen_string_literal: true

module Entities
  class TransactionEnrichment < Grape::Entity
    expose :id,                  documentation: { type: Integer }
    expose :merchant_id,         documentation: { type: Integer }
    expose :category_id,         documentation: { type: Integer }
    expose :merchant_rule_id,    documentation: { type: Integer }
    expose :source,              documentation: { type: String, desc: "rule / merchant_default / manual / user_rule / llm / payment_method_fallback" }
    expose :category_overridden, documentation: { type: "Boolean" }
    expose :confidence,          documentation: { type: Float }
    expose :model,               documentation: { type: String }
    expose :enriched_at,         documentation: { type: String }
    expose :merchant, using: Entities::Merchant, documentation: { type: "Entities::Merchant" }
    expose :category, using: Entities::Category, documentation: { type: "Entities::Category" }
    expose :effective_category, using: Entities::Category, documentation: { type: "Entities::Category" } do |e|
      e.category || e.merchant&.default_category
    end
  end
end
