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
require "rails_helper"

RSpec.describe UserHiddenCategory do
  it "rejects a second row for the same (user, category) with a category_id taken error" do
    user = create(:user)
    category = create(:category, user: user)
    UserHiddenCategory.create!(user: user, category: category)

    duplicate = UserHiddenCategory.new(user: user, category: category)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:category_id]).to include("has already been taken")
  end

  it "lets two different users hide the same category independently" do
    user_a = create(:user)
    user_b = create(:user)
    category = create(:category, user: user_a)

    expect {
      UserHiddenCategory.create!(user: user_a, category: category)
      UserHiddenCategory.create!(user: user_b, category: category)
    }.to change(UserHiddenCategory, :count).by(2)
  end
end
