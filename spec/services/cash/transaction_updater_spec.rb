# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::TransactionUpdater do
  def update_call(transaction:, **input_attrs)
    input = described_class::Input.new(**input_attrs)
    described_class.call(transaction: transaction, input: input)
  end

  def seed_manual_transaction(user:, **overrides)
    creator_input = Cash::TransactionCreator::Input.new(amount: "10", currency: overrides.delete(:currency) || "PLN", direction: "debit", title: "Initial")
    Cash::TransactionCreator.call(user: user, input: creator_input).transaction.tap do |tx|
      tx.update!(overrides) if overrides.any?
    end
  end

  it "rewrites the enrichment row as manual with category_overridden=true and updates fields on a happy edit" do
    user = create(:user)
    tx = seed_manual_transaction(user: user)
    category = create(:category, user: user, name: "Coffee", slug: "coffee", path: "food.coffee_#{SecureRandom.hex(2)}")

    result = update_call(transaction: tx, amount: "20", title: "Latte", category_id: category.id)

    expect(result.success?).to be(true)
    expect(tx.reload.amount_cents).to eq(2000)
    expect(tx.title).to eq("Latte")
    expect(tx.enrichment.source).to eq("manual")
    expect(tx.enrichment.category_overridden).to be(true)
    expect(tx.enrichment.category).to eq(category)
  end

  it "treats blank title and counterparty_name as 'clear' but keeps direction/booking_date when blank" do
    user = create(:user)
    tx = seed_manual_transaction(user: user)
    original_direction = tx.direction
    original_booking = tx.booking_date

    result = update_call(transaction: tx, title: "", counterparty_name: "", direction: "", booking_date: "")

    expect(result.success?).to be(true)
    tx.reload
    expect(tx.title).to be_blank
    expect(tx.counterparty_name).to be_blank
    expect(tx.direction).to eq(original_direction)
    expect(tx.booking_date).to eq(original_booking)
  end

  it "locks currency to the wallet's currency: amount '10,00' on an EUR wallet stays at 1000 cents (EUR scale)" do
    user = create(:user)
    eur_input = Cash::TransactionCreator::Input.new(amount: "5", currency: "EUR", direction: "debit")
    tx = Cash::TransactionCreator.call(user: user, input: eur_input).transaction

    update_call(transaction: tx, amount: "10,00")

    expect(tx.reload.amount_cents).to eq(1000)
    expect(tx.currency).to eq("EUR")
  end

  it "clearing category_id flips category_overridden to false and nulls the category" do
    user = create(:user)
    category = create(:category, user: user, name: "Coffee", slug: "coffee", path: "food.coffee_#{SecureRandom.hex(2)}")
    tx = seed_manual_transaction(user: user)
    update_call(transaction: tx, category_id: category.id)
    expect(tx.reload.enrichment.category_overridden).to be(true)

    update_call(transaction: tx, category_id: nil)

    expect(tx.reload.enrichment.category_overridden).to be(false)
    expect(tx.enrichment.category).to be_nil
  end

  it "drops a category_id belonging to another user but flips category_overridden because an id was supplied (documented quirk)" do
    user = create(:user)
    other_user = create(:user)
    foreign_category = create(:category, user: other_user, name: "Foreign", slug: "foreign", path: "foreign_#{SecureRandom.hex(2)}")
    tx = seed_manual_transaction(user: user)

    update_call(transaction: tx, category_id: foreign_category.id)

    expect(tx.reload.enrichment.category).to be_nil
    expect(tx.enrichment.category_overridden).to be(true)
  end

  it "builds a new enrichment row inline with source: manual when the legacy row had none" do
    user = create(:user)
    tx = seed_manual_transaction(user: user)
    tx.enrichment.destroy!
    expect(tx.reload.enrichment).to be_nil

    update_call(transaction: tx, title: "Refilled enrichment")

    tx.reload
    expect(tx.enrichment).to be_present
    expect(tx.enrichment.source).to eq("manual")
  end

  it "rolls back transaction and enrichment writes on a RecordInvalid (junk amount becomes presence error)" do
    user = create(:user)
    tx = seed_manual_transaction(user: user)
    original_cents = tx.amount_cents
    original_title = tx.title

    result = update_call(transaction: tx, amount: "totally-not-a-number", title: "Should not stick")

    expect(result.success?).to be(false)
    tx.reload
    expect(tx.amount_cents).to eq(original_cents)
    expect(tx.title).to eq(original_title)
  end
end
