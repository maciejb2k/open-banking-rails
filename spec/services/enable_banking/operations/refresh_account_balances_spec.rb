# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Operations::RefreshAccountBalances do
  it "fetches and persists raw_balances and stamps balances_synced_at on success" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN")
    fake_eb.set_balance(account_uid: uid, balance_cents: 250_00)
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, uid: uid, currency: "PLN")

    described_class.call(account)

    account.reload
    expect(account.balances_synced_at).to be_present
    expect(account.raw_balances).to be_present
    expect(JSON.parse(account.raw_balances)["balances"].first.dig("balance_amount", "amount")).to eq("250.00")
  end

  it "raises Operations::RefreshAccountBalances::Failed with the error_message when the API returns failure" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, uid: uid, currency: "PLN")
    fake_eb.simulate_failure(method: :get, path: "/accounts/#{uid}/balances", status: 503, error: "Bank temporarily unavailable")

    expect {
      described_class.call(account)
    }.to raise_error(described_class::Failed, /Bank temporarily unavailable/)
  end
end
