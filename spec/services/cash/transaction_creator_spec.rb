# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::TransactionCreator do
  def call(user:, **input_attrs)
    input = described_class::Input.new(**input_attrs)
    described_class.call(user: user, input: input)
  end

  it "persists a manual transaction in the user's PLN cash wallet and writes a manual-source enrichment" do
    user = create(:user)
    category = create(:category, user: user, name: "Coffee", slug: "coffee", path: "food.coffee_#{SecureRandom.hex(2)}")
    merchant = create(:merchant, user: user, name: "Cafe XYZ", slug: "cafe_xyz_#{SecureRandom.hex(2)}")

    result = call(user: user, amount: "12.34", currency: "PLN", direction: "debit", title: "Latte", category_id: category.id, merchant_id: merchant.id)

    expect(result.success?).to be(true)
    expect(result.transaction).to be_persisted
    expect(result.transaction.amount_cents).to eq(1234)
    expect(result.transaction.bank_account.manual?).to be(true)
    expect(result.transaction.bank_account.manual_owner).to eq(user)
    expect(result.enrichment.source).to eq("manual")
    expect(result.enrichment.category_overridden).to be(true)
    expect(result.enrichment.category).to eq(category)
    expect(result.enrichment.merchant).to eq(merchant)
    expect(result.enrichment.enriched_at).to be_present
  end

  it "normalizes currency input ' eur ' to EUR and resolves to the EUR wallet (uid namespacing)" do
    user = create(:user)

    result = call(user: user, amount: "10", currency: " eur ", direction: "debit")

    expect(result.success?).to be(true)
    expect(result.transaction.currency).to eq("EUR")
    expect(result.transaction.bank_account.uid).to eq("cash_#{user.id}_eur")
  end

  it "parses comma-decimal amounts and surfaces blank amount as a presence validation failure" do
    user = create(:user)

    parsed = call(user: user, amount: "12,34", currency: "PLN", direction: "debit")
    blank  = call(user: user, amount: "",     currency: "PLN", direction: "debit")

    expect(parsed.success?).to be(true)
    expect(parsed.transaction.amount_cents).to eq(1234)

    expect(blank.success?).to be(false)
    expect(blank.transaction).to be_a(ManualTransaction)
    expect(blank.error_messages.join).to match(/can't be blank|amount/i)
  end

  it "applies default direction=debit, payment_method=cash, booking_date=today when input is blank" do
    user = create(:user)

    travel_to(Date.new(2026, 5, 7)) do
      result = call(user: user, amount: "5", currency: "PLN")

      expect(result.success?).to be(true)
      expect(result.transaction.direction).to eq("debit")
      expect(result.transaction.payment_method).to eq("cash")
      expect(result.transaction.booking_date).to eq(Date.new(2026, 5, 7))
    end
  end

  it "silently drops another user's category_id but still flips category_overridden when an id was supplied (regression-worthy quirk)" do
    user = create(:user)
    other_user = create(:user)
    foreign_category = create(:category, user: other_user, name: "Foreign", slug: "foreign", path: "foreign_#{SecureRandom.hex(2)}")

    result = call(user: user, amount: "10", currency: "PLN", category_id: foreign_category.id)

    expect(result.success?).to be(true)
    expect(result.enrichment.category).to be_nil
    expect(result.enrichment.category_overridden).to be(true)
  end

  it "is idempotent at the wallet level — two consecutive creates reuse the same BankAccount uid" do
    user = create(:user)

    first  = call(user: user, amount: "1", currency: "PLN")
    second = call(user: user, amount: "2", currency: "PLN")

    expect(first.transaction.bank_account_id).to eq(second.transaction.bank_account_id)
    expect(BankAccount.where(uid: "cash_#{user.id}_pln").count).to eq(1)
  end

  it "wraps a junk amount as a presence validation failure on amount_cents (no raw ArgumentError)" do
    user = create(:user)

    result = call(user: user, amount: "totally-not-a-number", currency: "PLN")

    expect(result.success?).to be(false)
    expect(result.transaction).to be_a(ManualTransaction)
    expect(result.error_messages.join).to match(/blank/i)
  end
end
