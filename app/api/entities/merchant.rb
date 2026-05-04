# frozen_string_literal: true

module Entities
  class Merchant < Grape::Entity
    expose :id,                  documentation: { type: Integer }
    expose :name,                documentation: { type: String }
    expose :slug,                documentation: { type: String }
    expose :kind,                documentation: { type: String, desc: "company / person / unknown" }
    expose :source,              documentation: { type: String, desc: "user / llm / seed" }
    expose :logo_url,            documentation: { type: String }
    expose :notes,               documentation: { type: String }
    expose :default_category_id, documentation: { type: Integer }
    expose :confidence,          documentation: { type: Float }
    expose :model,               documentation: { type: String, desc: "LLM model name when source=llm" }
    expose :approved_at,         documentation: { type: String }
    expose :archived_at,         documentation: { type: String }
    expose :default_category,    using: Entities::Category, documentation: { type: "Entities::Category" }
  end
end
