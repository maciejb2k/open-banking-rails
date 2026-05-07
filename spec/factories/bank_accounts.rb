# frozen_string_literal: true

FactoryBot.define do
  factory :bank_account do
    sequence(:uid) { |n| "fake-account-#{n}-#{SecureRandom.hex(4)}" }
    sequence(:iban) { |n| "PL61109010140000071219#{format('%06d', n)}" }
    currency       { "PLN" }
    name           { "Test Account" }
    product        { "Personal" }
    cash_account_type { "CACC" }
    status         { "active" }
    manual         { false }
    all_account_ids { [] }
    tpp_credential

    trait :pln do
      currency { "PLN" }
    end

    trait :eur do
      currency { "EUR" }
    end

    trait :multi_currency do
      currency        { "EUR" }
      all_account_ids { [ { "scheme_name" => "IBAN", "identification" => "LT123456789012345678" } ] }
    end

    trait :cash do
      manual            { true }
      tpp_credential    { nil }
      manual_owner      { association :user }
      cash_account_type { "CASH" }
      uid               { "cash_#{SecureRandom.hex(8)}" }
      iban              { nil }
    end

    trait :closed do
      status { "inactive" }
    end
  end
end
