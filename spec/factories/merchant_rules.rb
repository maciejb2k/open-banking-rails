# frozen_string_literal: true

FactoryBot.define do
  factory :merchant_rule do
    transient do
      owner { association :user }
    end

    merchant { association :merchant, user: owner }
    user     { owner }
    kind     { "contains" }
    field    { "title" }
    pattern  { "BIEDRONKA" }
    source   { "user" }
    enabled  { true }
    priority { 0 }
    case_sensitive { false }

    trait :title_match do
      kind    { "contains" }
      field   { "title" }
      pattern { "BIEDRONKA" }
    end

    trait :counterparty_iban_match do
      kind    { "iban" }
      field   { "counterparty_iban" }
      pattern { "PL61109010140000071219812874" }
    end

    trait :payment_method_match do
      kind    { "exact" }
      field   { "payment_method" }
      pattern { "blik_atm" }
    end

    trait :active do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
