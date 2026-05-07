# frozen_string_literal: true

# == Schema Information
#
# Table name: bank_accounts
#
#  id                         :bigint           not null, primary key
#  account_servicer           :jsonb
#  all_account_ids            :jsonb            not null
#  balances_synced_at         :datetime
#  bban                       :string
#  cash_account_type          :string
#  currency                   :string
#  details                    :string
#  details_fetched_at         :datetime
#  iban                       :string
#  manual                     :boolean          default(FALSE), not null
#  name                       :string
#  product                    :string
#  raw_account_resource       :jsonb
#  raw_balances               :text
#  raw_details                :jsonb
#  status                     :string           default("active"), not null
#  transactions_synced_at     :datetime
#  uid                        :string           not null
#  usage                      :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  current_bank_connection_id :bigint
#  manual_owner_id            :bigint
#  tpp_credential_id          :bigint
#
# Indexes
#
#  index_bank_accounts_on_current_bank_connection_id  (current_bank_connection_id)
#  index_bank_accounts_on_iban                        (iban)
#  index_bank_accounts_on_manual                      (manual)
#  index_bank_accounts_on_manual_owner_id             (manual_owner_id)
#  index_bank_accounts_on_status                      (status)
#  index_bank_accounts_on_tpp_credential_id           (tpp_credential_id)
#  index_bank_accounts_on_uid                         (uid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (current_bank_connection_id => bank_connections.id)
#  fk_rails_...  (manual_owner_id => users.id)
#  fk_rails_...  (tpp_credential_id => tpp_credentials.id)
#
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
