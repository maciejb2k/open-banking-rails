# frozen_string_literal: true

module Entities
  class MerchantRule < Grape::Entity
    expose :id,             documentation: { type: Integer }
    expose :merchant_id,    documentation: { type: Integer }
    expose :field,          documentation: { type: String, desc: "title / counterparty_name / counterparty_iban" }
    expose :kind,           documentation: { type: String, desc: "contains / equals / regex / starts_with / ends_with" }
    expose :pattern,        documentation: { type: String }
    expose :case_sensitive, documentation: { type: "Boolean" }
    expose :priority,       documentation: { type: Integer }
    expose :enabled,        documentation: { type: "Boolean" }
    expose :source,         documentation: { type: String, desc: "user / llm / seed" }
    expose :confidence,     documentation: { type: Float }
    expose :model,          documentation: { type: String }
    expose :approved_at,    documentation: { type: String }
  end
end
