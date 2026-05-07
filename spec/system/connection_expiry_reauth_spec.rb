# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Bank connection expiry + reauth journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "surfaces an expired badge on the connection show page, walks the reauth flow back through the bank, and replaces the old connection on a successful callback" do
    user = create_seeded_user(email: "reauth-happy@example.test")
    credential = primary_credential(user)
    expired_connection = build_expired_connection(credential)

    fake_eb.add_aspsp(name: "PKO BP", country: "PL")
    fresh_session_id = fake_eb.add_session(aspsp_name: "PKO BP", country: "PL", valid_until: 90.days.from_now)
    fake_eb.add_account(
      session_id:    fresh_session_id,
      currency:      "PLN",
      balance_cents: 50_000_00,
      holder_name:   user.name,
      iban:          "PL61109010140000071219ABC001"
    )

    sign_in_as(user)
    visit admin_bank_connection_path(expired_connection)
    expect(page).to have_text("PKO BP")
    expect(page).to have_text("expired")

    click_button "Reauth (re-link with bank)"

    expect(page).to have_current_path(new_admin_bank_connection_path, ignore_query: true)
    expect(URI.parse(current_url).query).to include("replaces=#{expired_connection.id}")
    expect(page).to have_text("Re-authorize bank connection")
    expect(page).to have_select("bank_connection_request_form[aspsp_name]", selected: "PKO BP")

    state_token = EnableBanking::State.encode(
      user_id:                user.id,
      tpp_credential_id:      credential.id,
      aspsp_name:             "PKO BP",
      aspsp_country:          "PL",
      psu_type:               "personal",
      replaces_connection_id: expired_connection.id
    )

    visit oauth_callback_path(code: fresh_session_id, state: state_token)

    fresh_connection = user.bank_connections.where.not(id: expired_connection.id).order(:id).last
    expect(fresh_connection).to be_present
    expect(fresh_connection.bank_name).to eq("PKO BP")
    expect(fresh_connection.status).to eq("authorized")
    expect(fresh_connection.replaces_id).to eq(expired_connection.id)
    expect(fresh_connection.valid_until).to be > 60.days.from_now

    expired_connection.reload
    expect(expired_connection.status).to eq("replaced")
    expect(expired_connection.closed_at).to be_within(1.minute).of(Time.current)

    expect(page).to have_current_path(admin_bank_connection_path(fresh_connection))
  end

  it "leaves the expired connection untouched and surfaces a flash alert when the user cancels at the bank during reauth" do
    user = create_seeded_user(email: "reauth-cancel@example.test")
    credential = primary_credential(user)
    expired_connection = build_expired_connection(credential)
    sign_in_as(user)

    state_token = EnableBanking::State.encode(
      user_id:                user.id,
      tpp_credential_id:      credential.id,
      aspsp_name:             "PKO BP",
      aspsp_country:          "PL",
      psu_type:               "personal",
      replaces_connection_id: expired_connection.id
    )

    visit oauth_callback_path(error: "access_denied", state: state_token)

    expect(page).to have_current_path(admin_bank_connections_path)
    expect(page).to have_text("Authorization was cancelled or failed at the bank.")

    expect(user.bank_connections.where.not(id: expired_connection.id)).to be_empty
    expired_connection.reload
    expect(expired_connection.status).to eq("expired")
    expect(expired_connection.closed_at).to be_nil
  end

  it "rejects a callback whose state token references a different signed-in user with the State user mismatch flash and never creates a connection" do
    owner = create_seeded_user(email: "reauth-owner@example.test")
    intruder = User.create!(email: "intruder@example.test", password: "Password123!", name: "Intruder")
    credential = primary_credential(owner)
    expired_connection = build_expired_connection(credential)

    state_token = EnableBanking::State.encode(
      user_id:                owner.id,
      tpp_credential_id:      credential.id,
      aspsp_name:             "PKO BP",
      aspsp_country:          "PL",
      psu_type:               "personal",
      replaces_connection_id: expired_connection.id
    )

    sign_in_as(intruder)
    visit oauth_callback_path(code: "irrelevant", state: state_token)

    expect(page).to have_current_path(admin_bank_connections_path)
    expect(page).to have_text("State user mismatch.")
    expect(owner.bank_connections.where.not(id: expired_connection.id)).to be_empty
    expect(expired_connection.reload.status).to eq("expired")
  end

  def create_seeded_user(email:, name: "Reauth User")
    user = User.create!(email: email, password: "Password123!", name: name)
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)
    user
  end

  def primary_credential(user)
    user.tpp_credentials.create!(
      name:            "PKO BP (Reauth)",
      provider:        "enable_banking",
      environment:     "SANDBOX",
      status:          "active",
      primary:         true,
      application_id:  "fake-app-pko",
      redirect_url:    "http://localhost:3000/admin/oauth/enable_banking/callback",
      private_key_pem: "fake-pem"
    )
  end

  def build_expired_connection(credential)
    credential.bank_connections.create!(
      bank_slug:           "pko_bp",
      bank_country:        "PL",
      bank_name:           "PKO BP",
      status:              "expired",
      psu_type:            "personal",
      session_id:          "old-sess-#{SecureRandom.hex(4)}",
      valid_until:         1.day.ago,
      authorized_at:       180.days.ago,
      access_balances:     true,
      access_transactions: true
    )
  end
end
