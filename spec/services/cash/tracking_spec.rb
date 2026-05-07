# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::Tracking do
  it "backfills every eligible historical BLIK ATM debit on first enable and reports the count" do
    user = create(:user, :cash_on)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, bank_name: "Bank")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, currency: "PLN")
    eligible = Array.new(3) { |i| create(:bank_transaction, bank_account: account, payment_method: "blik_atm", direction: "debit", amount_cents: (i + 1) * 100_00) }

    result = described_class.enable!(user: user, currency: "PLN")

    expect(result.linked).to eq(3)
    expect(result.wallet.uid).to eq("cash_#{user.id}_pln")
    expect(ManualTransaction.where(linked_bank_transaction_id: eligible.map(&:id)).count).to eq(3)
  end

  it "is idempotent — running enable! a second time reports linked: 0 and creates no duplicate ManualTransactions" do
    user = create(:user, :cash_on)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, currency: "PLN")
    create(:bank_transaction, bank_account: account, payment_method: "blik_atm", direction: "debit", amount_cents: 100_00)
    described_class.enable!(user: user)

    second = described_class.enable!(user: user)

    expect(second.linked).to eq(0)
    expect(ManualTransaction.count).to eq(1)
  end

  it "links only blik_atm debits, ignoring blik_pos and blik_atm credits" do
    user = create(:user, :cash_on)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, currency: "PLN")
    create(:bank_transaction, bank_account: account, payment_method: "blik_pos", direction: "debit",  amount_cents: 50_00)
    create(:bank_transaction, bank_account: account, payment_method: "blik_atm", direction: "credit", amount_cents: 50_00)
    eligible = create(:bank_transaction, bank_account: account, payment_method: "blik_atm", direction: "debit", amount_cents: 100_00)

    result = described_class.enable!(user: user)

    expect(result.linked).to eq(1)
    expect(ManualTransaction.where(linked_bank_transaction_id: eligible.id)).to exist
  end

  it "creates the wallet but the linker no-ops when the user has track_cash false" do
    user = create(:user, track_cash: false)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, currency: "PLN")
    create(:bank_transaction, bank_account: account, payment_method: "blik_atm", direction: "debit", amount_cents: 100_00)

    result = described_class.enable!(user: user)

    expect(result.wallet).to be_persisted
    expect(result.linked).to eq(0)
    expect(ManualTransaction.count).to eq(0)
  end

  it "scopes the backfill to the requesting user — other users' BLIK ATM debits are not touched" do
    user_a = create(:user, :cash_on)
    user_b = create(:user, :cash_on)
    Seeders::Categories.call(user_a)
    tpp_a = create(:tpp_credential, user: user_a)
    tpp_b = create(:tpp_credential, user: user_b)
    account_a = create(:bank_account, tpp_credential: tpp_a, currency: "PLN")
    account_b = create(:bank_account, tpp_credential: tpp_b, currency: "PLN")
    create(:bank_transaction, bank_account: account_a, payment_method: "blik_atm", direction: "debit")
    create(:bank_transaction, bank_account: account_b, payment_method: "blik_atm", direction: "debit")

    result_a = described_class.enable!(user: user_a)

    expect(result_a.linked).to eq(1)
    expect(ManualTransaction.joins(:bank_account).where(bank_accounts: { manual_owner_id: user_b.id }).count).to eq(0)
  end
end
