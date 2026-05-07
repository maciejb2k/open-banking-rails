# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seeders::Categories do
  it "seeds the full category tree on first run, populating both kind and ltree path columns" do
    user = create(:user)

    described_class.call(user)

    expect(user.categories.count).to eq(described_class::DEFINITIONS.size)
    expect(user.categories.find_by(slug: "food").path.to_s).to eq("food")
    expect(user.categories.find_by(slug: "food_cooking_supermarket").path.to_s).to eq("food.cooking.supermarket")
    expect(user.categories.find_by(slug: "food_cooking_supermarket").kind).to eq("expense")
    expect(user.categories.find_by(slug: "money_transfers").kind).to eq("transfer")
  end

  it "is idempotent: a second run does not create duplicates and re-applies attribute changes via find_or_initialize_by(slug:)" do
    user = create(:user)
    described_class.call(user)
    food = user.categories.find_by(slug: "food")
    food.update!(color: "purple")

    expect {
      described_class.call(user)
    }.not_to change(user.categories, :count)

    expect(food.reload.color).to eq(described_class::PALETTE.fetch("food"))
  end

  it "scopes per user: seeding two users in the same DB yields two independent trees with no path collisions" do
    user_a = create(:user)
    user_b = create(:user)

    described_class.call(user_a)
    described_class.call(user_b)

    expect(user_a.categories.count).to eq(described_class::DEFINITIONS.size)
    expect(user_b.categories.count).to eq(described_class::DEFINITIONS.size)
    expect(user_a.categories.find_by(slug: "food").path).not_to eq(nil)
    expect(user_b.categories.find_by(slug: "food").path).not_to eq(nil)
  end
end
