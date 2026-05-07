# frozen_string_literal: true

# == Schema Information
#
# Table name: bank_connections
#
#  id                  :bigint           not null, primary key
#  access_balances     :boolean          default(TRUE), not null
#  access_transactions :boolean          default(TRUE), not null
#  authorized_at       :datetime
#  bank_country        :string           default("PL")
#  bank_name           :string
#  bank_slug           :string           not null
#  closed_at           :datetime
#  last_error          :text
#  last_refreshed_at   :datetime
#  last_synced_at      :datetime
#  psu_id_hash         :text
#  psu_type            :string           default("personal")
#  raw_session_payload :text
#  status              :string           default("pending"), not null
#  valid_until         :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  replaces_id         :bigint
#  session_id          :text
#  tpp_credential_id   :bigint           not null
#
# Indexes
#
#  index_bank_connections_lookup                (tpp_credential_id,bank_slug,status)
#  index_bank_connections_on_replaces_id        (replaces_id)
#  index_bank_connections_on_status             (status)
#  index_bank_connections_on_tpp_credential_id  (tpp_credential_id)
#  index_bank_connections_on_valid_until        (valid_until)
#
# Foreign Keys
#
#  fk_rails_...  (replaces_id => bank_connections.id)
#  fk_rails_...  (tpp_credential_id => tpp_credentials.id)
#
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
