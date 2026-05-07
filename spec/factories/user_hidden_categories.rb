# frozen_string_literal: true

# == Schema Information
#
# Table name: user_hidden_categories
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  category_id :bigint           not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_user_hidden_categories_on_category_id              (category_id)
#  index_user_hidden_categories_on_user_id                  (user_id)
#  index_user_hidden_categories_on_user_id_and_category_id  (user_id,category_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (category_id => categories.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :user_hidden_category do
    user
    category { association :category, user: user }
  end
end
