# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Operations::CreateConnection do
  it "creates a BankConnection plus child BankAccount(s) from the session payload" do
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL", status: "AUTHORIZED")
    fake_eb.add_account(session_id: session_id, uid: "fake-account-1", currency: "PLN", iban: "PL61109010140000071219812874", holder_name: "JAN KOWALSKI")
    state = { aspsp_name: "Fake Bank", aspsp_country: "PL", psu_type: "personal", replaces_connection_id: nil }

    bc = described_class.call(credential: tpp, code: session_id, state: state)

    expect(bc).to be_persisted
    expect(bc.bank_slug).to eq("fake_bank")
    expect(bc.bank_country).to eq("PL")
    expect(bc.status).to eq("authorized")
    expect(bc.session_id).to eq(session_id)
    expect(bc.current_bank_accounts.count).to eq(1)

    account = bc.current_bank_accounts.first
    expect(account.uid).to eq("fake-account-1")
    expect(account.iban).to eq("PL61109010140000071219812874")
    expect(account.tpp_credential).to eq(tpp)
  end

  it "raises CreateConnection::Failed when the session API call fails" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    state = { aspsp_name: "Fake Bank", aspsp_country: "PL", psu_type: "personal" }
    fake_eb.simulate_failure(method: :post, path: "/sessions", status: 400, error: "Invalid code")

    expect {
      described_class.call(credential: tpp, code: "any", state: state)
    }.to raise_error(described_class::Failed, /Invalid code/)
  end

  it "marks the previous connection as replaced when state[:replaces_connection_id] is supplied" do
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    old_connection = create(:bank_connection, tpp_credential: tpp, status: "authorized")
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL")
    fake_eb.add_account(session_id: session_id, uid: "fake-account-2")
    state = { aspsp_name: "Fake Bank", aspsp_country: "PL", psu_type: "personal", replaces_connection_id: old_connection.id }

    new_connection = described_class.call(credential: tpp, code: session_id, state: state)

    expect(new_connection).to be_persisted
    expect(old_connection.reload.status).to eq("replaced")
    expect(old_connection.closed_at).to be_present
  end
end
