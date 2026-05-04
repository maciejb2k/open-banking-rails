# frozen_string_literal: true

module Entities
  class LedgerEntry < Grape::Entity
    expose :source_type,         documentation: { type: String, desc: "BankTransaction / ManualTransaction" }
    expose :source_id,           documentation: { type: Integer }
    expose :bank_account_id,     documentation: { type: Integer }
    expose :amount,              using: Entities::Money do |e|
      e.amount
    end
    expose :signed_amount,       using: Entities::Money do |e|
      e.signed_amount
    end
    expose :direction,           documentation: { type: String, desc: "credit / debit" }
    expose :status,              documentation: { type: String, desc: "booked / pending" }
    expose :payment_method,      documentation: { type: String }
    expose :booking_date,        documentation: { type: String, format: "date" }
    expose :transaction_date,    documentation: { type: String, format: "date" }
    expose :title,               documentation: { type: String }
    expose :counterparty_name,   documentation: { type: String }
    expose :counterparty_kind,   documentation: { type: String, desc: "self / external / unknown" }
    expose :essential,           documentation: { type: "Boolean" }
    expose :recurring,           documentation: { type: "Boolean" }
    expose :recurrence_interval, documentation: { type: String }
    expose :enrichment_source,   documentation: { type: String }
    expose :merchant_id,         documentation: { type: Integer }
    expose :effective_category_id, documentation: { type: Integer }
    expose :category_path,       documentation: { type: String } do |e|
      e.category_path.to_s
    end
  end
end
