# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seeders::Showcase do
  it "runs from a fresh DB and produces a Result with the seeded user" do
    user = User.create!(email: "showcase@example.test", password: "Password123!", name: "Showcase User")
    result = described_class.call(user: user, fake_eb: fake_eb, fake_llm: fake_llm)
    expect(result.success?).to be(true), "expected success, got: #{result.error}"
    expect(result.user).to eq(user.reload)
  end

  it "creates the canonical category tree, multiple TPP credentials, and at least one bank connection" do
    user = User.create!(email: "showcase2@example.test", password: "Password123!", name: "Showcase Two")
    result = described_class.call(user: user, fake_eb: fake_eb, fake_llm: fake_llm)
    expect(result.tpp_credentials.size).to be >= 2
    expect(result.connections.size).to be >= 1
    expect(user.categories.count).to be >= 50
    expect(user.merchants.count).to be >= 1
  end

  it "produces bank transactions through the production sync path (not direct AR creation)" do
    user = User.create!(email: "showcase3@example.test", password: "Password123!", name: "Showcase Three")
    result = described_class.call(user: user, fake_eb: fake_eb, fake_llm: fake_llm)
    expect(result.bank_transactions.size).to be >= 30
    expect(result.bank_transactions.map(&:bank_account_id).uniq.size).to be >= 2
  end

  it "produces manual cash transactions via Cash::TransactionCreator" do
    user = User.create!(email: "showcase4@example.test", password: "Password123!", name: "Showcase Four")
    result = described_class.call(user: user, fake_eb: fake_eb, fake_llm: fake_llm)
    expect(result.cash_transactions.size).to be >= 1
    expect(result.cash_transactions).to all(be_a(ManualTransaction))
  end

  it "produces sync schedules with at least one paused entry" do
    user = User.create!(email: "showcase5@example.test", password: "Password123!", name: "Showcase Five")
    result = described_class.call(user: user, fake_eb: fake_eb, fake_llm: fake_llm)
    expect(result.sync_schedules).to all(be_a(SyncSchedule))
    expect(result.sync_schedules.map(&:enabled)).to include(true).or include(false)
  end

  it "produces a non-zero LedgerEntry sum that matches the source-table sum" do
    user = User.create!(email: "showcase6@example.test", password: "Password123!", name: "Showcase Six")
    described_class.call(user: user, fake_eb: fake_eb, fake_llm: fake_llm)

    bank_sum   = BankTransaction.for_user(user).sum(:amount_cents)
    manual_sum = ManualTransaction.for_user(user).sum(:amount_cents)
    ledger_sum = LedgerEntry.for_user(user).sum(:amount_cents)
    expect(ledger_sum).to eq(bank_sum + manual_sum)
    expect(ledger_sum).to be > 0
  end

  it "fails fast when called without a user" do
    expect {
      described_class.call(user: nil, fake_eb: fake_eb, fake_llm: fake_llm)
    }.not_to raise_error
    result = described_class.call(user: nil, fake_eb: fake_eb, fake_llm: fake_llm)
    expect(result.success?).to be(false)
  end
end
