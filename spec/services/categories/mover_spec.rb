# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categories::Mover do
  def make_tree(user)
    food   = create(:category, user: user, name: "Food",        slug: "food",    path: "food")
    cooking = create(:category, user: user, name: "Cooking",    slug: "cooking", path: "food.cooking")
    market  = create(:category, user: user, name: "Supermarket", slug: "supermarket", path: "food.cooking.supermarket")
    leisure = create(:category, user: user, name: "Leisure",    slug: "leisure", path: "leisure")
    [ food, cooking, market, leisure ]
  end

  it "moves a leaf to a new parent and rewrites only its own path (no descendants to bother)" do
    user = create(:user)
    food, cooking, _market, leisure = make_tree(user)

    result = described_class.call(category: cooking, attributes: {}, parent_path: "leisure")

    expect(result.success?).to be(true)
    expect(cooking.reload.path.to_s).to eq("leisure.cooking")
    expect(food.reload.path.to_s).to eq("food")
    expect(leisure.reload.path.to_s).to eq("leisure")
  end

  it "moves an entire subtree, rewriting every descendant's path in a single SQL UPDATE" do
    user = create(:user)
    food, cooking, market, leisure = make_tree(user)
    extra_market = create(:category, user: user, name: "Convenience", slug: "convenience", path: "food.cooking.convenience")

    described_class.call(category: cooking, attributes: {}, parent_path: "leisure")

    expect(cooking.reload.path.to_s).to eq("leisure.cooking")
    expect(market.reload.path.to_s).to eq("leisure.cooking.supermarket")
    expect(extra_market.reload.path.to_s).to eq("leisure.cooking.convenience")
    expect(food.reload.path.to_s).to eq("food")
  end

  it "is a no-op for a same-parent move (saved_change_to_path? false → no descendant rewrite)" do
    user = create(:user)
    _food, cooking, market, _leisure = make_tree(user)

    expect {
      described_class.call(category: cooking, attributes: {}, parent_path: "food")
    }.not_to(change { market.reload.path.to_s })

    expect(cooking.reload.path.to_s).to eq("food.cooking")
  end

  it "returns Result(success?: false) without rewriting descendants on a validation failure" do
    user = create(:user)
    _food, cooking, market, _leisure = make_tree(user)

    result = described_class.call(category: cooking, attributes: { kind: "expenseish" }, parent_path: "leisure")

    expect(result.success?).to be(false)
    expect(cooking.reload.path.to_s).to eq("food.cooking")
    expect(market.reload.path.to_s).to eq("food.cooking.supermarket")
  end

  it "scopes the descendant rewrite to the moving category's user — sibling user's same-prefixed paths are not touched" do
    user_a = create(:user)
    user_b = create(:user)
    _food_a, cooking_a, market_a, leisure_a = make_tree(user_a)

    user_b_food = create(:category, user: user_b, name: "Food", slug: "food", path: "food_other_user_#{SecureRandom.hex(2)}")
    user_b_food.update!(path: "food_b_root", slug: "food_b_root")
    user_b_cooking = create(:category, user: user_b, name: "Cooking", slug: "cooking", path: "food_b_root.cooking")

    described_class.call(category: cooking_a, attributes: {}, parent_path: "leisure")

    expect(cooking_a.reload.path.to_s).to eq("leisure.cooking")
    expect(market_a.reload.path.to_s).to eq("leisure.cooking.supermarket")
    expect(user_b_cooking.reload.path.to_s).to eq("food_b_root.cooking")
    expect(leisure_a).to be_present
  end
end
