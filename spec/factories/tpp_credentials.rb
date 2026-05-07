# frozen_string_literal: true

# == Schema Information
#
# Table name: tpp_credentials
#
#  id                      :bigint           not null, primary key
#  cert_expires_at         :datetime
#  environment             :string
#  last_verification_error :text
#  last_verified_at        :datetime
#  metadata                :jsonb            not null
#  name                    :string           not null
#  primary                 :boolean          default(FALSE), not null
#  private_key_pem         :text
#  provider                :string           default("enable_banking"), not null
#  public_cert_pem         :text
#  redirect_url            :string
#  status                  :string           default("pending"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  application_id          :text
#  user_id                 :bigint           not null
#
# Indexes
#
#  index_one_primary_tpp_credential_per_user  (user_id) UNIQUE WHERE ("primary" = true)
#  index_tpp_credentials_on_provider          (provider)
#  index_tpp_credentials_on_status            (status)
#  index_tpp_credentials_on_user_id           (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
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
