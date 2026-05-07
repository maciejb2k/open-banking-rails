# frozen_string_literal: true

module Entities
  class Money < Grape::Entity
    expose :cents,    documentation: { type: Integer, desc: "Amount in minor units" }
    expose :currency, documentation: { type: String,  desc: "ISO-4217 code" }

    def cents
      object&.cents
    end

    def currency
      object&.currency&.iso_code
    end
  end
end
