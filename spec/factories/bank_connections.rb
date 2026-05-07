# frozen_string_literal: true

FactoryBot.define do
  factory :bank_connection do
    tpp_credential
    sequence(:bank_slug) { |n| "fake_bank_#{n}" }
    bank_country         { "PL" }
    bank_name            { "Fake Bank" }
    status               { "authorized" }
    psu_type             { "personal" }
    sequence(:session_id) { |n| "session-#{n}-#{SecureRandom.hex(4)}" }
    valid_until          { 30.days.from_now }
    authorized_at        { Time.current }
    access_balances      { true }
    access_transactions  { true }

    trait :active do
      status      { "authorized" }
      valid_until { 30.days.from_now }
    end

    trait :expired do
      status      { "expired" }
      valid_until { 1.day.ago }
    end

    trait :pending_auth do
      status        { "pending" }
      authorized_at { nil }
    end

    trait :revoked do
      status { "revoked" }
    end
  end
end
