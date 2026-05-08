# frozen_string_literal: true

# == Schema Information
#
# Table name: transaction_enrichments
#
#  id                  :bigint           not null, primary key
#  category_overridden :boolean          default(FALSE), not null
#  confidence          :decimal(4, 3)
#  enrichable_type     :string           not null
#  enriched_at         :datetime
#  model               :string
#  notes               :text
#  source              :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  category_id         :bigint
#  enrichable_id       :bigint           not null
#  merchant_id         :bigint
#  merchant_rule_id    :bigint
#
# Indexes
#
#  idx_enrichments_on_enrichable                      (enrichable_type,enrichable_id) UNIQUE
#  index_transaction_enrichments_on_category_id       (category_id)
#  index_transaction_enrichments_on_enrichable        (enrichable_type,enrichable_id)
#  index_transaction_enrichments_on_merchant_id       (merchant_id)
#  index_transaction_enrichments_on_merchant_rule_id  (merchant_rule_id)
#  index_transaction_enrichments_on_source            (source)
#
# Foreign Keys
#
#  fk_rails_...  (category_id => categories.id)
#  fk_rails_...  (merchant_id => merchants.id)
#  fk_rails_...  (merchant_rule_id => merchant_rules.id)
#
FactoryBot.define do
  factory :transaction_enrichment do
    enrichable { association :bank_transaction }
    source     { "system_rule" }
    confidence { 0.95 }
    enriched_at { Time.current }

    trait :rule do
      source { "system_rule" }
    end

    trait :llm do
      source     { "llm_rule" }
      confidence { 0.9 }
      model      { "gemini-2.5-flash" }
    end

    trait :manual do
      source              { "manual" }
      category_overridden { true }
      confidence          { 1.0 }
    end

    trait :high_confidence do
      confidence { 0.95 }
    end

    trait :low_confidence do
      confidence { 0.4 }
    end
  end
end
