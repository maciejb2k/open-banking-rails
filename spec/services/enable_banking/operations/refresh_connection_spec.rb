# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Operations::RefreshConnection do
  it "maps EB session status AUTHORIZED to authorized and clears last_error" do
    tpp = create(:tpp_credential)
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL", status: "AUTHORIZED")
    connection = create(:bank_connection, tpp_credential: tpp, session_id: session_id, status: "authorized", last_error: "previous boom")

    described_class.call(connection)

    expect(connection.reload.status).to eq("authorized")
    expect(connection.last_error).to be_nil
    expect(connection.last_refreshed_at).to be_present
  end

  it "maps EB session status EXPIRED to expired" do
    tpp = create(:tpp_credential)
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL", status: "EXPIRED")
    connection = create(:bank_connection, tpp_credential: tpp, session_id: session_id, status: "authorized")

    described_class.call(connection)

    expect(connection.reload.status).to eq("expired")
  end

  it "maps an unknown EB session status to error rather than masking it" do
    tpp = create(:tpp_credential)
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL", status: "WAT")
    connection = create(:bank_connection, tpp_credential: tpp, session_id: session_id, status: "authorized")

    described_class.call(connection)

    expect(connection.reload.status).to eq("error")
  end

  it "flips connection.status to expired when /sessions/{id} returns 401 (consent revoked at the bank)" do
    tpp = create(:tpp_credential)
    session_id = "expired-session-#{SecureRandom.hex(4)}"
    connection = create(:bank_connection, tpp_credential: tpp, session_id: session_id, status: "authorized")
    fake_eb.simulate_failure(method: :get, path: "/sessions/#{session_id}", status: 401, error: "Unauthorized")

    expect {
      described_class.call(connection)
    }.to raise_error(described_class::Failed, /Unauthorized/)

    expect(connection.reload.status).to eq("expired")
    expect(connection.last_error).to include("HTTP 401")
  end

  it "leaves connection.status untouched on a 5xx and surfaces it in last_error (transient bank-side issue)" do
    tpp = create(:tpp_credential)
    session_id = "wobbly-session-#{SecureRandom.hex(4)}"
    connection = create(:bank_connection, tpp_credential: tpp, session_id: session_id, status: "authorized")
    fake_eb.simulate_failure(method: :get, path: "/sessions/#{session_id}", status: 502, error: "Bad Gateway")

    expect {
      described_class.call(connection)
    }.to raise_error(described_class::Failed)

    expect(connection.reload.status).to eq("authorized")
    expect(connection.last_error).to include("HTTP 502")
  end
end
