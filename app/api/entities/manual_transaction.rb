# frozen_string_literal: true

module Entities
  class ManualTransaction < Grape::Entity
    expose :id,                documentation: { type: Integer }
    expose :bank_account_id,   documentation: { type: Integer }
    expose :amount,            using: Entities::Money do |t|
      t.amount
    end
    expose :signed_amount, using: Entities::Money do |t|
      ::Money.new(t.direction == "credit" ? t.amount_cents : -t.amount_cents, t.currency)
    end
    expose :direction,         documentation: { type: String }
    expose :status,            documentation: { type: String }
    expose :booking_date,      documentation: { type: String, format: "date" }
    expose :transaction_date,  documentation: { type: String, format: "date" }
    expose :title,             documentation: { type: String }
    expose :note,              documentation: { type: String }
    expose :counterparty_name, documentation: { type: String }
    expose :counterparty_kind, documentation: { type: String }
    expose :payment_method,    documentation: { type: String }
    expose :source,            documentation: { type: String, desc: "manual / atm_link" }
    expose :linked_bank_transaction_id, documentation: { type: Integer }
    expose :enrichment, using: Entities::TransactionEnrichment, documentation: { type: "Entities::TransactionEnrichment" }
    expose :created_at,        documentation: { type: String }
    expose :updated_at,        documentation: { type: String }
  end
end
