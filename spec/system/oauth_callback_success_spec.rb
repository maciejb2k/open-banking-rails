# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth callback success journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "decodes a valid state token and creates a BankConnection with one BankAccount on a happy /callback round-trip" do
    user = create_user_with_credential(name: "Happy Path")
    fake_eb.add_aspsp(name: "PKO BP", country: "PL")
    session_id = fake_eb.add_session(aspsp_name: "PKO BP", country: "PL", valid_until: 30.days.from_now)
    fake_eb.add_account(
      session_id:    session_id,
      currency:      "PLN",
      balance_cents: 25_000_00,
      holder_name:   user.name,
      iban:          "PL61109010140000071219812874"
    )

    sign_in_via_form(user)

    state_token = EnableBanking::State.encode(
      user_id:           user.id,
      tpp_credential_id: user.tpp_credentials.first.id,
      aspsp_name:        "PKO BP",
      aspsp_country:     "PL",
      psu_type:          "personal"
    )

    visit oauth_callback_path(code: session_id, state: state_token)

    connection = user.bank_connections.first
    expect(connection).to be_present
    expect(connection.bank_name).to eq("PKO BP")
    expect(connection.status).to eq("authorized")
    expect(connection.session_id).to eq(session_id)
    expect(connection.current_bank_accounts.count).to eq(1)
    expect(page).to have_current_path(admin_bank_connection_path(connection))
    expect(page).to have_text("PKO BP")
    expect(page).to have_text(/connected|account/i)
  end

  it "rejects a callback whose decoded state belongs to another user with the state-mismatch alert" do
    user_a = create_user_with_credential(name: "Mismatch A", email_prefix: "mismatch-a")
    user_b = User.create!(email: "mismatch-b-#{SecureRandom.hex(4)}@example.test", password: "Password123!", name: "Mismatch B")

    sign_in_via_form(user_a)

    state_token = EnableBanking::State.encode(
      user_id:           user_b.id,
      tpp_credential_id: user_a.tpp_credentials.first.id,
      aspsp_name:        "PKO BP",
      aspsp_country:     "PL",
      psu_type:          "personal"
    )

    visit oauth_callback_path(code: "any-code", state: state_token)

    expect(page).to have_current_path(admin_bank_connections_path, ignore_query: true)
    expect(page).to have_text(/mismatch/i)
    expect(BankConnection.count).to eq(0)
  end

  it "rejects a callback with a syntactically invalid state token, redirects to the connections index, and creates no BankConnection" do
    user = create_user_with_credential(name: "Bad State")

    sign_in_via_form(user)

    visit oauth_callback_path(code: "any-code", state: "not-a-real-state-token")

    expect(page).to have_current_path(admin_bank_connections_path, ignore_query: true)
    expect(page).to have_text(/invalid|expired/i)
    expect(BankConnection.count).to eq(0)
  end

  it "rejects a callback for a credential that does not belong to the signed-in user with the credential-no-longer-exists alert" do
    user = create_user_with_credential(name: "Cross Credential A")
    other_user = User.create!(email: "other-#{SecureRandom.hex(4)}@example.test", password: "Password123!", name: "Other Owner")
    other_credential = other_user.tpp_credentials.create!(
      name:            "Other TPP",
      provider:        "enable_banking",
      environment:     "SANDBOX",
      status:          "active",
      primary:         true,
      application_id:  "fake-app-other",
      redirect_url:    "http://localhost:3000/admin/oauth/enable_banking/callback",
      private_key_pem: "fake-pem-other"
    )

    sign_in_via_form(user)

    state_token = EnableBanking::State.encode(
      user_id:           user.id,
      tpp_credential_id: other_credential.id,
      aspsp_name:        "PKO BP",
      aspsp_country:     "PL",
      psu_type:          "personal"
    )

    visit oauth_callback_path(code: "any-code", state: state_token)

    expect(page).to have_current_path(admin_bank_connections_path, ignore_query: true)
    expect(page).to have_text(/credential/i)
    expect(BankConnection.count).to eq(0)
  end

  def create_user_with_credential(name:, email_prefix: "happy")
    user = User.create!(
      email:    "#{email_prefix}-#{SecureRandom.hex(4)}@example.test",
      password: "Password123!",
      name:     name
    )
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)
    user.tpp_credentials.create!(
      name:            "#{name} TPP",
      provider:        "enable_banking",
      environment:     "SANDBOX",
      status:          "active",
      primary:         true,
      application_id:  "fake-app-#{SecureRandom.hex(4)}",
      redirect_url:    "http://localhost:3000/admin/oauth/enable_banking/callback",
      private_key_pem: "fake-pem"
    )
    user
  end

  def sign_in_via_form(user)
    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"
  end
end
