# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Operations::CloseConnection do
  it "calls Api::CloseSession then flips connection.status to closed and stamps closed_at" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL")
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized", session_id: session_id)

    described_class.call(connection)

    expect(connection.reload.status).to eq("closed")
    expect(connection.closed_at).to be_present
    expect(connection.last_error).to be_nil
    expect(fake_eb.recorded_calls).to include(hash_including(method: :delete, path: "/sessions/#{session_id}"))
  end

  it "swallows a remote DELETE failure and still flips the local connection to closed (best-effort invariant)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    session_id = "session-#{SecureRandom.hex(4)}"
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized", session_id: session_id)
    fake_eb.simulate_failure(method: :delete, path: "/sessions/#{session_id}", status: 500, error: "boom")

    expect {
      described_class.call(connection)
    }.not_to raise_error

    expect(connection.reload.status).to eq("closed")
    expect(connection.closed_at).to be_present
  end

  it "skips the remote DELETE entirely when the connection is not authorized (already-closed/expired short-circuit)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "expired", session_id: "stale-session")

    described_class.call(connection)

    expect(connection.reload.status).to eq("closed")
    expect(fake_eb.recorded_calls).not_to include(hash_including(path: "/sessions/stale-session"))
  end

  it "skips the remote DELETE when session_id is blank (legacy connection without a remote session)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, status: "authorized", session_id: nil)

    described_class.call(connection)

    expect(connection.reload.status).to eq("closed")
    expect(fake_eb.recorded_calls.select { |c| c[:method] == :delete }).to be_empty
  end
end
