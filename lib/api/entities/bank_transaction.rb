# frozen_string_literal: true

module Entities
  class BankTransaction < Grape::Entity
    expose :id,                    documentation: { type: Integer }
    expose :external_id,           documentation: { type: String }
    expose :bank_account_id,       documentation: { type: Integer }
    expose :amount, using: Entities::Money do |t|
      t.amount
    end
    expose :signed_amount, using: Entities::Money do |t|
      ::Money.new(t.direction == "credit" ? t.amount_cents : -t.amount_cents, t.currency)
    end
    expose :direction,             documentation: { type: String }
    expose :status,                documentation: { type: String }
    expose :booking_date,          documentation: { type: String, format: "date" }
    expose :value_date,            documentation: { type: String, format: "date" }
    expose :transaction_date,      documentation: { type: String, format: "date" }
    expose :title,                 documentation: { type: String }
    expose :counterparty_name,     documentation: { type: String }
    expose :counterparty_iban,     documentation: { type: String }
    expose :counterparty_kind,     documentation: { type: String }
    expose :payment_method,        documentation: { type: String }
    expose :type_hint,             documentation: { type: String }
    expose :bank_transaction_code, documentation: { type: String }
    expose :fetched_at,            documentation: { type: String }
    expose :enrichment, using: Entities::TransactionEnrichment, documentation: { type: "Entities::TransactionEnrichment" }
  end
end
