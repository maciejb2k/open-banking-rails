# frozen_string_literal: true

# == Schema Information
#
# Table name: personal_access_tokens
#
#  id           :bigint           not null, primary key
#  last_four    :string(4)        not null
#  last_used_at :datetime
#  name         :string           not null
#  revoked_at   :datetime
#  token_digest :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_personal_access_tokens_on_token_digest      (token_digest) UNIQUE
#  index_personal_access_tokens_on_user_id           (user_id)
#  index_personal_access_tokens_on_user_id_and_name  (user_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
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
