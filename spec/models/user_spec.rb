# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                       :bigint           not null, primary key
#  email                    :string           default(""), not null
#  encrypted_password       :string           default(""), not null
#  name                     :string
#  remember_created_at      :datetime
#  reset_password_sent_at   :datetime
#  reset_password_token     :string
#  reveal_hidden_categories :boolean          default(FALSE), not null
#  track_cash               :boolean          default(FALSE), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
require "rails_helper"

RSpec.describe User do
  it "returns true for hides_category? on every descendant of an explicitly hidden parent" do
    user = create(:user)
    food = create(:category, user: user, slug: "food", path: "food")
    cooking = create(:category, user: user, slug: "food_cooking", path: "food.cooking")
    super_market = create(:category, user: user, slug: "food_cooking_supermarket", path: "food.cooking.supermarket")
    unrelated = create(:category, user: user, slug: "transport", path: "transport")
    UserHiddenCategory.create!(user: user, category: food)

    expect(user.hides_category?(food)).to be(true)
    expect(user.hides_category?(cooking)).to be(true)
    expect(user.hides_category?(super_market.id)).to be(true)
    expect(user.hides_category?(unrelated)).to be(false)
    expect(user.hides_category?(nil)).to be(false)
    expect(user.hides_category?("")).to be(false)
  end

  it "returns an empty Set from hidden_subtree_ids when no categories are hidden" do
    user = create(:user)
    create(:category, user: user, slug: "food", path: "food")

    expect(user.hidden_subtree_ids).to be_a(Set)
    expect(user.hidden_subtree_ids).to be_empty
  end

  it "unions synced and manual bank-account ids in all_bank_account_ids and excludes other users' accounts" do
    user_a = create(:user)
    user_b = create(:user)
    tpp_a = create(:tpp_credential, user: user_a)
    tpp_b = create(:tpp_credential, user: user_b)
    synced_a = create(:bank_account, tpp_credential: tpp_a)
    cash_a   = create(:bank_account, :cash, manual_owner: user_a)
    synced_b = create(:bank_account, tpp_credential: tpp_b)

    ids = user_a.all_bank_account_ids
    expect(ids).to include(synced_a.id, cash_a.id)
    expect(ids).not_to include(synced_b.id)
  end

  it "normalises own_ibans by stripping whitespace, upcasing, and merging alternate IBANs without duplicates" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    create(:bank_account, tpp_credential: tpp,
           iban: "  pl61109010140000071219812874  ",
           all_account_ids: [
             { "scheme_name" => "IBAN", "identification" => "PL61109010140000071219812874" },
             { "scheme_name" => "IBAN", "identification" => " LT123456789012345678 " }
           ])

    expect(user.own_ibans).to contain_exactly("PL61109010140000071219812874", "LT123456789012345678")
  end

  it "deduplicates and uppercases own_holder_names regardless of bank-side casing" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    create(:bank_account, tpp_credential: tpp, name: "MACIEJ TEST")
    create(:bank_account, tpp_credential: tpp, name: "Maciej Test")
    create(:bank_account, tpp_credential: tpp, name: "")

    expect(user.own_holder_names).to contain_exactly("MACIEJ TEST")
  end

  it "computes initials as the first letter of the first two name parts, falling back to ? on blank" do
    expect(build(:user, name: "Maciek Biel").initials).to eq("MB")
    expect(build(:user, name: "Cher").initials).to eq("C")
    expect(build(:user, name: "Łukasz").initials).to eq("Ł")
    expect(build(:user, name: "").initials).to eq("?")
    expect(build(:user, name: nil).initials).to eq("?")
  end

  it "falls back to email in display_name when name is blank" do
    expect(build(:user, name: "Maciek", email: "m@example.test").display_name).to eq("Maciek")
    expect(build(:user, name: "", email: "m@example.test").display_name).to eq("m@example.test")
    expect(build(:user, name: nil, email: "m@example.test").display_name).to eq("m@example.test")
  end
end
