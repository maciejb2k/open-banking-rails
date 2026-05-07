# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth callback error journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "redirects to the bank connections index with the cancel-or-fail alert when the bank reports access_denied and creates no BankConnection" do
    user = create_user_with_credential(name: "Cancelled")

    sign_in_via_form(user)

    visit oauth_callback_path(error: "access_denied", state: "irrelevant", code: "irrelevant")

    expect(page).to have_current_path(admin_bank_connections_path, ignore_query: true)
    expect(page).to have_text(/cancel|fail/i)
    expect(BankConnection.count).to eq(0)
  end

  it "rejects a callback whose state token cannot be decoded and creates no BankConnection" do
    user = create_user_with_credential(name: "Invalid State")

    sign_in_via_form(user)

    visit oauth_callback_path(state: "garbage-state-token", code: "any-code")

    expect(page).to have_current_path(admin_bank_connections_path, ignore_query: true)
    expect(page).to have_text(/invalid|expired/i)
    expect(BankConnection.count).to eq(0)
  end

  it "rejects a callback whose state references a tpp_credential that no longer exists with the credential-no-longer-exists alert" do
    user = create_user_with_credential(name: "Missing Credential")
    credential = user.tpp_credentials.first

    state_token = EnableBanking::State.encode(
      user_id:           user.id,
      tpp_credential_id: credential.id,
      aspsp_name:        "PKO BP",
      aspsp_country:     "PL",
      psu_type:          "personal"
    )
    BankAccount.where(tpp_credential_id: credential.id).delete_all
    BankConnection.where(tpp_credential_id: credential.id).delete_all
    credential.destroy!

    sign_in_via_form(user)

    visit oauth_callback_path(state: state_token, code: "any-code")

    expect(page).to have_current_path(admin_bank_connections_path, ignore_query: true)
    expect(page).to have_text(/credential/i)
    expect(BankConnection.count).to eq(0)
  end

  it "rejects a callback with a blank authorization code and surfaces the missing-code alert" do
    user = create_user_with_credential(name: "Blank Code")
    state_token = EnableBanking::State.encode(
      user_id:           user.id,
      tpp_credential_id: user.tpp_credentials.first.id,
      aspsp_name:        "PKO BP",
      aspsp_country:     "PL",
      psu_type:          "personal"
    )

    sign_in_via_form(user)

    visit oauth_callback_path(state: state_token, code: "")

    expect(page).to have_current_path(admin_bank_connections_path, ignore_query: true)
    expect(page).to have_text(/code/i)
    expect(BankConnection.count).to eq(0)
  end

  it "surfaces a CreateConnection::Failed message as the redirect alert when the operation raises Failed mid-flight" do
    user = create_user_with_credential(name: "Op Failed")
    state_token = EnableBanking::State.encode(
      user_id:           user.id,
      tpp_credential_id: user.tpp_credentials.first.id,
      aspsp_name:        "PKO BP",
      aspsp_country:     "PL",
      psu_type:          "personal"
    )

    allow(EnableBanking::Operations::CreateConnection).to receive(:call)
      .and_raise(EnableBanking::Operations::CreateConnection::Failed.new("Bank refused the auth"))

    sign_in_via_form(user)

    visit oauth_callback_path(state: state_token, code: "any-code")

    expect(page).to have_current_path(admin_bank_connections_path, ignore_query: true)
    expect(page).to have_text("Bank refused the auth")
    expect(BankConnection.count).to eq(0)
  end

  it "redirects an anonymous /callback hit through the Devise sign-in gate without creating a BankConnection" do
    create_user_with_credential(name: "Anon")

    visit oauth_callback_path(state: "x", code: "y")

    expect(page).to have_current_path(new_user_session_path, ignore_query: true)
    expect(BankConnection.count).to eq(0)
  end

  def create_user_with_credential(name:, email_prefix: "err")
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
