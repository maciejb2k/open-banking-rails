# frozen_string_literal: true

# == Schema Information
#
# Table name: bank_transactions
#
#  id                    :bigint           not null, primary key
#  amount_cents          :bigint           not null
#  bank_transaction_code :string
#  booking_date          :date             not null
#  counterparty_iban     :string
#  counterparty_kind     :string           default("unknown"), not null
#  counterparty_name     :string
#  currency              :string(3)        not null
#  direction             :string           not null
#  fetched_at            :datetime         not null
#  payment_method        :string
#  raw_payload           :text             not null
#  status                :string           default("booked"), not null
#  title                 :text
#  transaction_date      :date
#  type_hint             :string
#  value_date            :date
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  bank_account_id       :bigint           not null
#  external_id           :string           not null
#
# Indexes
#
#  index_bank_transactions_on_bank_account_id                   (bank_account_id)
#  index_bank_transactions_on_bank_account_id_and_booking_date  (bank_account_id,booking_date)
#  index_bank_transactions_on_bank_account_id_and_external_id   (bank_account_id,external_id) UNIQUE
#  index_bank_transactions_on_counterparty_kind                 (counterparty_kind)
#  index_bank_transactions_on_payment_method                    (payment_method)
#  index_bank_transactions_on_status                            (status)
#
# Foreign Keys
#
#  fk_rails_...  (bank_account_id => bank_accounts.id)
#
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
