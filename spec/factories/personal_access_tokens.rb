# frozen_string_literal: true

FactoryBot.define do
  factory :personal_access_token do
    sequence(:name) { |n| "Token #{n}" }
    user

    transient do
      sequence(:raw_token) { |n| "#{PersonalAccessToken::PREFIX}#{format('%016x%016x', n, n)}#{SecureRandom.hex(8)}" }
    end

    token_digest { PersonalAccessToken.digest_for(raw_token) }
    last_four    { raw_token.last(4) }

    trait :revoked do
      revoked_at { 1.minute.ago }
    end

    trait :recently_used do
      last_used_at { 1.minute.ago }
    end
  end
end
