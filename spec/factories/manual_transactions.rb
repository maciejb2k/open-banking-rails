# frozen_string_literal: true

FactoryBot.define do
  factory :manual_transaction do
    transient do
      user { association :user }
    end

    bank_account     { association :bank_account, :cash, manual_owner: user }
    created_by_user  { user }
    amount_cents     { 50_00 }
    currency         { "PLN" }
    direction        { "debit" }
    status           { "booked" }
    payment_method   { "cash" }
    source           { "manual" }
    counterparty_kind { "unknown" }
    booking_date     { Date.current }
    transaction_date { Date.current }
    title            { "Cash entry" }

    trait :pln do
      currency { "PLN" }
    end

    trait :eur do
      currency       { "EUR" }
      bank_account   { association :bank_account, :cash, manual_owner: user, currency: "EUR" }
    end

    trait :linked do
      transient do
        linked_bank_transaction { association :bank_transaction, :atm_withdrawal }
      end
      linked_bank_transaction_id { linked_bank_transaction.id }
      source                     { "atm_link" }
    end
  end
end
