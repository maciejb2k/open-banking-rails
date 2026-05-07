# frozen_string_literal: true

FactoryBot.define do
  factory :bank_transaction do
    bank_account
    sequence(:external_id) { |n| "fake-tx-#{n}-#{SecureRandom.hex(4)}" }
    amount_cents      { 100_00 }
    currency          { "PLN" }
    direction         { "debit" }
    status            { "booked" }
    payment_method    { "card" }
    counterparty_kind { "external" }
    booking_date      { Date.current }
    transaction_date  { Date.current }
    title             { "Test transaction" }
    raw_payload       { "{}" }
    fetched_at        { Time.current }

    trait :debit do
      direction { "debit" }
    end

    trait :credit do
      direction { "credit" }
    end

    trait :booked do
      status { "booked" }
    end

    trait :pending do
      status { "pending" }
    end

    trait :card do
      payment_method { "card" }
    end

    trait :transfer do
      payment_method { "transfer" }
    end

    trait :atm_withdrawal do
      payment_method { "blik_atm" }
      direction      { "debit" }
    end

    trait :small do
      amount_cents { 9_99 }
    end

    trait :large do
      amount_cents { 5_000_00 }
    end
  end
end
