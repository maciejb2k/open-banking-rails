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
require "rails_helper"

RSpec.describe Category do
  it "rejects slug values that violate the lowercase/digits/underscore/dash format" do
    user = create(:user)

    [ "Food", "food groceries", "żabka" ].each do |bad_slug|
      record = build(:category, user: user, name: "X", slug: bad_slug, path: "root_#{SecureRandom.hex(4)}")
      record.valid?
      expect(record.errors[:slug]).to include("must be lowercase letters, digits, underscores, dashes"), "slug=#{bad_slug.inspect} should fail"
    end

    [ "food", "food_groceries", "a-b", "42" ].each do |good_slug|
      record = build(:category, user: user, name: "X", slug: good_slug, path: "p_#{SecureRandom.hex(4)}")
      record.valid?
      expect(record.errors[:slug]).to be_empty, "slug=#{good_slug.inspect} should pass"
    end
  end

  it "scopes slug uniqueness per user (different users may share, same user may not)" do
    user_a = create(:user)
    user_b = create(:user)
    create(:category, user: user_a, name: "Groceries", slug: "groceries", path: "groceries_a")
    create(:category, user: user_b, name: "Groceries", slug: "groceries", path: "groceries_b")

    duplicate = build(:category, user: user_a, name: "Other", slug: "groceries", path: "groceries_a_dup")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:slug]).to include("has already been taken")
  end

  it "scopes path uniqueness per user (different users may share, same user may not)" do
    user_a = create(:user)
    user_b = create(:user)
    create(:category, user: user_a, name: "Food", slug: "food", path: "food.cooking.supermarket")

    cross_user = build(:category, user: user_b, name: "Other", slug: "supermarket_other", path: "food.cooking.supermarket")
    expect(cross_user).to be_valid

    same_user = build(:category, user: user_a, name: "Other", slug: "supermarket_other", path: "food.cooking.supermarket")
    expect(same_user).not_to be_valid
    expect(same_user.errors[:path]).to include("has already been taken")
  end

  it "fills slug from the last segment of path when slug is blank, and leaves an explicit slug alone" do
    user = create(:user)

    derived = build(:category, user: user, name: "Cooking", slug: "", path: "food.cooking_#{SecureRandom.hex(2)}")
    derived.valid?
    expect(derived.slug).to eq(derived.path.split(".").last)

    explicit = build(:category, user: user, name: "Cooking", slug: "supermarket", path: "food.cooking_#{SecureRandom.hex(2)}")
    explicit.valid?
    expect(explicit.slug).to eq("supermarket")
  end

  it "archive! is idempotent — second call leaves archived_at unchanged" do
    user = create(:user)
    record = create(:category, user: user)

    record.archive!
    expect(record).to be_archived
    first_archived_at = record.archived_at

    travel_to(Time.current + 1.hour) do
      record.archive!
    end

    expect(record.reload.archived_at).to eq(first_archived_at)
  end

  it "exposes ltree helpers (descendants, children, ancestors, parent, depth) over a 3-level tree" do
    user = create(:user)
    food = create(:category, user: user, name: "Food", slug: "food", path: "food")
    cooking = create(:category, user: user, name: "Cooking", slug: "cooking", path: "food.cooking")
    supermarket = create(:category, user: user, name: "Supermarket", slug: "supermarket", path: "food.cooking.supermarket")

    expect(food.descendants).to contain_exactly(cooking, supermarket)
    expect(food.children).to contain_exactly(cooking)
    expect(supermarket.ancestors.order(Arel.sql("nlevel(path)"))).to eq([ food, cooking ])
    expect(supermarket.parent).to eq(cooking)
    expect(food.depth).to eq(0)
    expect(food).to be_root
    expect(cooking.depth).to eq(1)
    expect(supermarket.breadcrumb_names).to eq([ "Food", "Cooking", "Supermarket" ])
  end

  it "under_path accepts a Category, a string, an array of mixed types, and returns none for empty input" do
    user = create(:user)
    drink = create(:category, user: user, name: "Drink", slug: "drink", path: "drink")
    drink_water = create(:category, user: user, name: "Water", slug: "water", path: "drink.water")
    food = create(:category, user: user, name: "Food", slug: "food", path: "food_x")

    by_record = described_class.under_path(drink).pluck(:id)
    by_string = described_class.under_path("drink").pluck(:id)
    by_array  = described_class.under_path([ food, "drink" ]).pluck(:id)

    expect(by_record).to contain_exactly(drink.id, drink_water.id)
    expect(by_string).to contain_exactly(drink.id, drink_water.id)
    expect(by_array).to contain_exactly(food.id, drink.id, drink_water.id)
    expect(described_class.under_path([])).to be_empty
  end

  it "rejects a kind value outside the canonical list and accepts every member of KINDS" do
    user = create(:user)

    bad = build(:category, user: user, name: "X", slug: "x", path: "x_bad", kind: "expenseish")
    expect(bad).not_to be_valid
    expect(bad.errors[:kind]).to include("is not included in the list")

    Category::KINDS.each do |k|
      good = build(:category, user: user, name: "X", slug: "ok_#{k}", path: "ok_#{k}_#{SecureRandom.hex(2)}", kind: k)
      expect(good).to be_valid, "kind=#{k.inspect} should pass"
    end
  end
end
