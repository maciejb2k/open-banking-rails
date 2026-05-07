# frozen_string_literal: true

# == Schema Information
#
# Table name: merchant_rules
#
#  id             :bigint           not null, primary key
#  approved_at    :datetime
#  case_sensitive :boolean          default(FALSE), not null
#  confidence     :decimal(4, 3)
#  enabled        :boolean          default(TRUE), not null
#  field          :string           not null
#  kind           :string           not null
#  model          :string
#  pattern        :string           not null
#  priority       :integer          default(0), not null
#  source         :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  approved_by_id :bigint
#  merchant_id    :bigint           not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_merchant_rules_on_approved_by_id        (approved_by_id)
#  index_merchant_rules_on_enabled_and_priority  (enabled,priority)
#  index_merchant_rules_on_field_and_pattern     (field,pattern)
#  index_merchant_rules_on_merchant_id           (merchant_id)
#  index_merchant_rules_on_source                (source)
#  index_merchant_rules_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (approved_by_id => users.id)
#  fk_rails_...  (merchant_id => merchants.id)
#  fk_rails_...  (user_id => users.id)
#
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
