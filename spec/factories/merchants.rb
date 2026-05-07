# frozen_string_literal: true

# == Schema Information
#
# Table name: merchants
#
#  id                  :bigint           not null, primary key
#  approved_at         :datetime
#  archived_at         :datetime
#  confidence          :decimal(4, 3)
#  kind                :string
#  logo_url            :string
#  model               :string
#  name                :string           not null
#  notes               :text
#  slug                :string           not null
#  source              :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  approved_by_id      :bigint
#  default_category_id :bigint
#  user_id             :bigint           not null
#
# Indexes
#
#  index_merchants_on_approved_by_id       (approved_by_id)
#  index_merchants_on_archived_at          (archived_at)
#  index_merchants_on_default_category_id  (default_category_id)
#  index_merchants_on_name                 (name)
#  index_merchants_on_source               (source)
#  index_merchants_on_user_id              (user_id)
#  index_merchants_on_user_id_and_slug     (user_id,slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (approved_by_id => users.id)
#  fk_rails_...  (default_category_id => categories.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :merchant do
    user
    sequence(:name) { |n| "Merchant #{n}" }
    sequence(:slug) { |n| "merchant_#{n}" }
    source          { "user" }
    kind            { "company" }

    trait :system do
      source      { "system" }
      approved_at { Time.current }
    end

    trait :user_source do
      source      { "user" }
      approved_at { Time.current }
    end

    trait :llm do
      source     { "llm" }
      confidence { 0.9 }
      model      { "gemini-2.5-flash" }
    end

    trait :with_default_category do
      default_category { association :category, user: user }
    end
  end
end
