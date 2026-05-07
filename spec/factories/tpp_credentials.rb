# frozen_string_literal: true

FactoryBot.define do
  factory :tpp_credential do
    user
    sequence(:name) { |n| "TPP Credential #{n}" }
    provider        { "enable_banking" }
    environment     { "SANDBOX" }
    status          { "pending" }
    primary         { false }
    application_id  { "fake-app-id-#{SecureRandom.hex(4)}" }
    redirect_url    { "http://localhost:3000/admin/oauth/enable_banking/callback" }
    private_key_pem { OpenSSL::PKey::RSA.new(2048).to_pem }

    trait :verified do
      status           { "active" }
      last_verified_at { Time.current }
    end

    trait :pending do
      status { "pending" }
    end

    trait :primary do
      primary { true }
    end
  end
end
