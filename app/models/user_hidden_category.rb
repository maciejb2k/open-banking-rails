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
  # Per-user join: which categories the user has marked "private". Owned
  # by User (User#hidden_categories). Always-on — the act of selecting a
  # category here triggers server-side bullet rendering everywhere it
  # would otherwise render its name. Independent of the topbar
  # privacy_mode cookie (that one masks all `.sensitive` content for
  # screen-share; this one targets specific categories regardless of mode).

  belongs_to :user
  belongs_to :category

  validates :category_id, uniqueness: { scope: :user_id }
end
