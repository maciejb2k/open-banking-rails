# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categories::Creator do
  it "creates a root category, deriving the slug from the name and composing the path from slug only" do
    user = create(:user)
    result = described_class.call(user: user, attributes: { name: "Food & Drink", kind: "expense" })

    expect(result.success?).to be(true)
    category = result.category
    expect(category.slug).to eq("food_drink")
    expect(category.path.to_s).to eq("food_drink")
    expect(category.user).to eq(user)
  end

  it "creates a child category under parent_path with composed dotted path" do
    user = create(:user)
    described_class.call(user: user, attributes: { name: "Food", kind: "expense" })

    result = described_class.call(user: user, attributes: { name: "Coffee", kind: "expense" }, parent_path: "food")

    expect(result.success?).to be(true)
    expect(result.category.slug).to eq("coffee")
    expect(result.category.path.to_s).to eq("food.coffee")
  end

  it "auto-numbers a slug collision (groceries → groceries_2)" do
    user = create(:user)
    described_class.call(user: user, attributes: { name: "Groceries", kind: "expense" })

    second = described_class.call(user: user, attributes: { name: "Groceries", kind: "expense" })

    expect(second.success?).to be(true)
    expect(second.category.slug).to eq("groceries_2")
    expect(second.category.path.to_s).to eq("groceries_2")
  end

  it "returns Result(success?: false) carrying validation errors when name is blank" do
    user = create(:user)
    result = described_class.call(user: user, attributes: { kind: "expense" })

    expect(result.success?).to be(false)
    expect(result.error).to match(/can't be blank|name/i)
  end

  it "scopes slug uniqueness per user — different users may share the same slug" do
    user_a = create(:user)
    user_b = create(:user)
    result_a = described_class.call(user: user_a, attributes: { name: "Groceries", kind: "expense" })
    result_b = described_class.call(user: user_b, attributes: { name: "Groceries", kind: "expense" }, parent_path: "groceries_b_root_#{SecureRandom.hex(2)}")

    described_class.call(user: user_b, attributes: { name: "Root", kind: "expense", slug: "groceries_b_root_#{SecureRandom.hex(2)}" })

    expect(result_a.success?).to be(true)
    expect(result_a.category.slug).to eq("groceries")
  end
end
