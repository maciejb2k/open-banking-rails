# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::TopMerchants do
  it "returns rows ordered by SUM(amount_cents) DESC limited to the requested number" do
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    food = user.categories.find_by!(path: "food.eating_out.restaurant")
    big = create(:merchant, user: user, name: "Big Spend")
    small = create(:merchant, user: user, name: "Small Spend")
    [ 100_00, 50_00 ].each do |cents|
      tx = create(:bank_transaction, bank_account: account, amount_cents: cents, currency: "PLN", direction: "debit")
      create(:transaction_enrichment, enrichable: tx, merchant: big, category: food)
    end
    tx = create(:bank_transaction, bank_account: account, amount_cents: 30_00, currency: "PLN", direction: "debit")
    create(:transaction_enrichment, enrichable: tx, merchant: small, category: food)

    rows = described_class.call(LedgerEntry.for_user(user), user: user, currency: "PLN", limit: 8)

    expect(rows.length).to eq(2)
    expect(rows.map { |r| r.merchant.id }).to eq([ big.id, small.id ])
    expect(rows.first.amount_cents).to eq(150_00)
    expect(rows.first.count).to eq(2)
  end

  it "respects the limit parameter" do
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    food = user.categories.find_by!(path: "food.eating_out.restaurant")
    3.times do |i|
      m = create(:merchant, user: user, name: "M#{i}")
      tx = create(:bank_transaction, bank_account: account, amount_cents: (i + 1) * 1000, currency: "PLN", direction: "debit")
      create(:transaction_enrichment, enrichable: tx, merchant: m, category: food)
    end

    rows = described_class.call(LedgerEntry.for_user(user), user: user, currency: "PLN", limit: 2)

    expect(rows.length).to eq(2)
  end

  it "wraps amount_cents in a Money instance via Row#amount" do
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    food = user.categories.find_by!(path: "food.eating_out.restaurant")
    merchant = create(:merchant, user: user)
    tx = create(:bank_transaction, bank_account: account, amount_cents: 12345, currency: "PLN", direction: "debit")
    create(:transaction_enrichment, enrichable: tx, merchant: merchant, category: food)

    row = described_class.call(LedgerEntry.for_user(user), user: user, currency: "PLN").first

    expect(row.amount).to be_a(Money)
    expect(row.amount.cents).to eq(12345)
    expect(row.amount.currency.iso_code).to eq("PLN")
  end
end
