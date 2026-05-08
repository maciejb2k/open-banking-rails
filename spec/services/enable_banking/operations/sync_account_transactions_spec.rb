# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Operations::SyncAccountTransactions do
  it "inserts new transactions, normalizes and resolves counterparty_kind, and stamps transactions_synced_at" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user, status: "active")
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, uid: uid, currency: "PLN")
    fake_eb.add_transaction(account_uid: uid, amount_cents: 12345, direction: "debit", title: "Coffee", counterparty_name: "Cafe XYZ", counterparty_iban: "PL61109010140000071219812874")

    outcome = described_class.call(account, date_from: Date.current - 30, date_to: Date.current)

    expect(outcome.inserted).to eq(1)
    expect(outcome.skipped).to eq(0)
    expect(account.bank_transactions.count).to eq(1)
    tx = account.bank_transactions.first
    expect(tx.title).to eq("Coffee")
    expect(tx.counterparty_iban).to eq("PL61109010140000071219812874")
    expect(tx.counterparty_kind).to eq("external")
    expect(account.reload.transactions_synced_at).to be_present
  end

  it "is idempotent: re-running over the same payload skips the duplicate by external_id (sync idempotency invariant)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, uid: uid, currency: "PLN")
    fake_eb.add_transaction(account_uid: uid, amount_cents: 5000, direction: "debit", title: "Lunch", external_id: "stable-tx-1")

    first  = described_class.call(account, date_from: Date.current - 30, date_to: Date.current)
    second = described_class.call(account, date_from: Date.current - 30, date_to: Date.current)

    expect(first.inserted).to eq(1)
    expect(second.inserted).to eq(0)
    expect(second.skipped).to eq(1)
    expect(account.bank_transactions.count).to eq(1)
  end

  it "raises Operations::SyncAccountTransactions::Failed when the API returns failure" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, uid: uid, currency: "PLN")
    fake_eb.simulate_failure(method: :get, path: "/accounts/#{uid}/transactions", status: 500, error: "Internal Server Error")

    expect {
      described_class.call(account, date_from: Date.current - 30, date_to: Date.current)
    }.to raise_error(described_class::Failed, /Internal Server Error/)
  end

  it "uses BackfillWindow.default_date_from on a never-synced account when date_from is nil" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized", bank_slug: "revolut")
    session_id = fake_eb.add_session(aspsp_name: "Revolut", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, uid: uid, currency: "PLN", transactions_synced_at: nil)

    travel_to(Date.new(2026, 5, 7)) do
      described_class.call(account)

      get_call = fake_eb.recorded_calls.find { |c| c[:method] == :get && c[:path] == "/accounts/#{uid}/transactions" }
      expect(get_call[:params][:date_from].to_s).to eq("2026-02-06")
    end
  end

  it "on a 401 from /transactions probes /sessions/{id} via RefreshConnection and flips connection.status to expired when the session is no longer AUTHORIZED" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL", status: "EXPIRED")
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized", session_id: session_id)
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, uid: uid, currency: "PLN")
    fake_eb.simulate_failure(method: :get, path: "/accounts/#{uid}/transactions", status: 401, error: "Unauthorized")

    expect {
      described_class.call(account, date_from: Date.current - 30, date_to: Date.current)
    }.to raise_error(described_class::Failed, /Unauthorized/)

    expect(connection.reload.status).to eq("expired")
  end

  it "on a 401 from /transactions leaves connection.status untouched when /sessions/{id} still reports AUTHORIZED (transient glitch)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL", status: "AUTHORIZED")
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized", session_id: session_id)
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, uid: uid, currency: "PLN")
    fake_eb.simulate_failure(method: :get, path: "/accounts/#{uid}/transactions", status: 401, error: "Unauthorized")

    expect {
      described_class.call(account, date_from: Date.current - 30, date_to: Date.current)
    }.to raise_error(described_class::Failed)

    expect(connection.reload.status).to eq("authorized")
  end

  it "uses INCREMENTAL_OVERLAP back from transactions_synced_at on subsequent syncs" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized", bank_slug: "revolut")
    session_id = fake_eb.add_session(aspsp_name: "Revolut", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, uid: uid, currency: "PLN", transactions_synced_at: Time.utc(2026, 5, 6, 12, 0))

    described_class.call(account, date_to: Date.new(2026, 5, 7))

    get_call = fake_eb.recorded_calls.find { |c| c[:method] == :get && c[:path] == "/accounts/#{uid}/transactions" }
    expect(get_call[:params][:date_from].to_s).to eq("2026-04-29")
  end
end
