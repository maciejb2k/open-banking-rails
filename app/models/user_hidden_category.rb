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
class UserHiddenCategory < ApplicationRecord
  # Independent of the privacy_mode cookie - this targets specific
  # categories regardless of mode. The act of selecting one triggers
  # server-side bullet rendering wherever the name would render.
  belongs_to :user
  belongs_to :category

  validates :category_id, uniqueness: { scope: :user_id }
end
