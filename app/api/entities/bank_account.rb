# frozen_string_literal: true

module Entities
  class BankAccount < Grape::Entity
    expose :id,                     documentation: { type: Integer }
    expose :uid,                    documentation: { type: String, desc: "Provider-side account id" }
    expose :name,                   documentation: { type: String }
    expose :iban,                   documentation: { type: String }
    expose :bban,                   documentation: { type: String }
    expose :currency,               documentation: { type: String }
    expose :status,                 documentation: { type: String }
    expose :manual,                 documentation: { type: "Boolean", desc: "True for cash wallets" }
    expose :product,                documentation: { type: String }
    expose :cash_account_type,      documentation: { type: String }
    expose :details,                documentation: { type: String }
    expose :details_fetched_at,     documentation: { type: String }
    expose :balances_synced_at,     documentation: { type: String }
    expose :transactions_synced_at, documentation: { type: String }

    expose :balances, documentation: { type: "Array", desc: "Raw Berlin Group balances (ITAV/ITBD/CLBD/OPBD…)" } do |a|
      a.parsed_balances.map { |b|
        amount   = b.dig("balance_amount", "amount")
        currency = b.dig("balance_amount", "currency")
        {
          name:           b["name"],
          type:           b["balance_type"],
          amount_cents:   amount.present? ? ::Money.from_amount(BigDecimal(amount.to_s), currency).cents : nil,
          currency:       currency,
          reference_date: b["reference_date"],
          last_change_at: b["last_change_date_time"]
        }
      }
    end
  end
end
