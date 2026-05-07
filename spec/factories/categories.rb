# frozen_string_literal: true

# == Schema Information
#
# Table name: categories
#
#  id          :bigint           not null, primary key
#  archived_at :datetime
#  color       :string
#  essential   :boolean          default(FALSE), not null
#  icon        :string
#  kind        :string           default("expense"), not null
#  name        :string           not null
#  path        :ltree
#  position    :integer          default(0), not null
#  slug        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_categories_on_archived_at       (archived_at)
#  index_categories_on_path              (path) USING gist
#  index_categories_on_user_id           (user_id)
#  index_categories_on_user_id_and_path  (user_id,path) UNIQUE
#  index_categories_on_user_id_and_slug  (user_id,slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :category do
    user
    sequence(:name) { |n| "Category #{n}" }
    sequence(:slug) { |n| "category_#{n}" }
    sequence(:path) { |n| "category_#{n}" }
    kind            { "expense" }
    color           { "emerald" }
    icon            { "tag" }
    essential       { false }
    position        { 0 }

    trait :spend do
      kind { "expense" }
    end

    trait :income do
      kind { "income" }
    end

    trait :transfer do
      kind { "transfer" }
    end

    trait :savings do
      kind { "savings" }
    end

    trait :ignore do
      kind { "ignored" }
    end

    trait :archived do
      archived_at { Time.current }
    end
  end
end
