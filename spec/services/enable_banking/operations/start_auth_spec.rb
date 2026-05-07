# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Operations::StartAuth do
  Form = Struct.new(:aspsp_name, :aspsp_country, :psu_type, :valid_days, keyword_init: true)

  it "POSTs to /auth with a signed state and returns the bank's redirect URL on success" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    form = Form.new(aspsp_name: "Fake Bank", aspsp_country: "PL", psu_type: "personal", valid_days: 90)

    url = described_class.call(credential: tpp, form: form, current_user: user)

    expect(url).to start_with("https://fake.enablebanking.test/auth?state=")
    auth_call = fake_eb.recorded_calls.find { |c| c[:method] == :post && c[:path] == "/auth" }
    expect(auth_call).to be_present
    expect(auth_call[:params][:aspsp]).to include(name: "Fake Bank", country: "PL")
    expect(auth_call[:params][:psu_type]).to eq("personal")
    expect(auth_call[:params][:state]).to be_present
  end

  it "raises Operations::StartAuth::Failed when the auth API returns a failure" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    form = Form.new(aspsp_name: "Fake Bank", aspsp_country: "PL", psu_type: "personal", valid_days: 90)
    fake_eb.simulate_failure(method: :post, path: "/auth", status: 400, error: "Bank refused")

    expect {
      described_class.call(credential: tpp, form: form, current_user: user)
    }.to raise_error(described_class::Failed, /Bank refused/)
  end

  it "passes replaces_connection_id through the encoded state when supplied" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    old_connection = create(:bank_connection, tpp_credential: tpp)
    form = Form.new(aspsp_name: "Fake Bank", aspsp_country: "PL", psu_type: "personal", valid_days: 90)

    url = described_class.call(credential: tpp, form: form, current_user: user, replaces_connection_id: old_connection.id)
    expect(url).to be_present

    auth_call = fake_eb.recorded_calls.find { |c| c[:method] == :post && c[:path] == "/auth" }
    expect(auth_call[:params][:state]).to be_present
  end
end
