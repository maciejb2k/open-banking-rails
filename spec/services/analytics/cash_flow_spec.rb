# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::CashFlow do
  def setup_user_with_history
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    user.reload
    [ user, account ]
  end

  def seed_tx(account, kind:, on:, amount_cents:, direction:, payment_method: "card")
    user = account.tpp_credential.user
    category_path = case kind
    when "expense" then "food.cooking.supermarket"
    when "income"  then "income.work.salary"
    when "transfer" then "money.transfers.own"
    end
    category = user.categories.find_by(path: category_path)
    tx = create(:bank_transaction, bank_account: account, amount_cents: amount_cents, currency: "PLN", direction: direction, payment_method: payment_method, booking_date: on)
    create(:transaction_enrichment, enrichable: tx, source: "system_fallback", category: category)
    tx
  end

  it "totals split spend and income from the LedgerEntry view, computing net as income - spend" do
    user, account = setup_user_with_history
    seed_tx(account, kind: "expense", on: Date.new(2026, 5, 1), amount_cents: 100_00, direction: "debit")
    seed_tx(account, kind: "expense", on: Date.new(2026, 5, 2), amount_cents: 50_00,  direction: "debit")
    seed_tx(account, kind: "income",  on: Date.new(2026, 5, 3), amount_cents: 500_00, direction: "credit")

    scope = LedgerEntry.where(bank_account_id: account.id).where(currency: "PLN").booked
    totals = described_class.totals(scope)

    expect(totals[:spend_cents]).to eq(150_00)
    expect(totals[:income_cents]).to eq(500_00)
    expect(totals[:net_cents]).to eq(350_00)
  end

  it "excludes transfers from spend and income (they cancel across own accounts)" do
    user, account = setup_user_with_history
    seed_tx(account, kind: "expense",  on: Date.new(2026, 5, 1), amount_cents: 100_00, direction: "debit")
    seed_tx(account, kind: "transfer", on: Date.new(2026, 5, 2), amount_cents: 999_00, direction: "debit",  payment_method: "internal_transfer")
    seed_tx(account, kind: "transfer", on: Date.new(2026, 5, 3), amount_cents: 999_00, direction: "credit", payment_method: "internal_transfer")

    scope = LedgerEntry.where(bank_account_id: account.id).where(currency: "PLN").booked
    totals = described_class.totals(scope)

    expect(totals[:spend_cents]).to eq(100_00)
    expect(totals[:income_cents]).to eq(0)
  end

  it "series returns one Point per bucket with spend/income split, gap-filled with zero" do
    user, account = setup_user_with_history
    seed_tx(account, kind: "expense", on: Date.new(2026, 5, 1), amount_cents: 100_00, direction: "debit")
    seed_tx(account, kind: "income",  on: Date.new(2026, 5, 3), amount_cents: 500_00, direction: "credit")

    period = Analytics::Period.new(from: Date.new(2026, 5, 1), to: Date.new(2026, 5, 3))
    scope = LedgerEntry.where(bank_account_id: account.id).where(currency: "PLN").booked.in_range(period.from, period.to)
    series = described_class.series(scope, period: period, currency: "PLN")

    expect(series.length).to eq(3)
    expect(series.map { |p| [ p.date, p.spend_cents, p.income_cents ] }).to eq([
      [ Date.new(2026, 5, 1), 100_00, 0 ],
      [ Date.new(2026, 5, 2), 0,      0 ],
      [ Date.new(2026, 5, 3), 0,      500_00 ]
    ])
  end
end
