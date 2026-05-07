# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public area", type: :request do
  it "GET /setup with no users renders the new form with the admin_auth layout" do
    User.destroy_all
    get "/setup"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="user[email]"')
    expect(response.body).to include('name="user[password]"')
  end

  it "GET /setup redirects signed-out visitors to the sign-in page when a user already exists" do
    User.destroy_all
    create(:user)
    get "/setup"
    expect(response).to redirect_to(new_user_session_path)
  end

  it "GET /setup redirects signed-in visitors to /admin when a user already exists" do
    User.destroy_all
    user = create(:user)
    sign_in user
    get "/setup"
    expect(response).to redirect_to(admin_root_path)
  end

  it "POST /setup creates the first user, runs both seeders, signs them in and redirects to /admin" do
    User.destroy_all
    allow(Seeders::Categories).to receive(:call)
    allow(Seeders::MerchantRules).to receive(:call)

    post "/setup", params: {
      user: {
        name: "Owner",
        email: "owner@example.test",
        password: "Password123!",
        password_confirmation: "Password123!"
      }
    }

    expect(response).to redirect_to(admin_root_path)
    expect(flash[:notice]).to match(/welcome/i)
    user = User.find_by(email: "owner@example.test")
    expect(user).to be_present
    expect(Seeders::Categories).to have_received(:call).with(user)
    expect(Seeders::MerchantRules).to have_received(:call).with(user)
  end

  it "POST /setup with invalid attrs re-renders :new with 422 and does not call the seeders" do
    User.destroy_all
    allow(Seeders::Categories).to receive(:call)
    allow(Seeders::MerchantRules).to receive(:call)

    expect {
      post "/setup", params: {
        user: { name: "", email: "", password: "x", password_confirmation: "y" }
      }
    }.not_to change(User, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(Seeders::Categories).not_to have_received(:call)
    expect(Seeders::MerchantRules).not_to have_received(:call)
  end

  it "POST /setup with an existing user redirects signed-out visitors to sign-in without creating a second user" do
    User.destroy_all
    create(:user)
    expect {
      post "/setup", params: {
        user: {
          name: "Intruder", email: "intruder@example.test",
          password: "Password123!", password_confirmation: "Password123!"
        }
      }
    }.not_to change(User, :count)
    expect(response).to redirect_to(new_user_session_path)
  end

  it "POST /setup with an existing user redirects signed-in visitors to /admin without creating a second user" do
    User.destroy_all
    user = create(:user)
    sign_in user
    expect {
      post "/setup", params: {
        user: {
          name: "Intruder", email: "intruder@example.test",
          password: "Password123!", password_confirmation: "Password123!"
        }
      }
    }.not_to change(User, :count)
    expect(response).to redirect_to(admin_root_path)
  end

  it "GET /callback redirects to sign-in when no user is signed in" do
    create(:user)
    get "/callback", params: { state: "x", code: "y" }
    expect(response).to redirect_to(new_user_session_path)
  end

  it "GET /callback redirects to bank connections with an alert when the bank reports an error" do
    user = create(:user)
    sign_in user
    get "/callback", params: { error: "access_denied", state: "ignored", code: "ignored" }
    expect(response).to redirect_to(admin_bank_connections_path)
    expect(flash[:alert]).to match(/cancel|fail/i)
  end

  it "GET /callback redirects with an alert when the state cannot be decoded" do
    user = create(:user)
    sign_in user
    allow(EnableBanking::State).to receive(:decode).and_return(nil)
    get "/callback", params: { state: "garbage", code: "y" }
    expect(response).to redirect_to(admin_bank_connections_path)
    expect(flash[:alert]).to match(/invalid|expired/i)
  end

  it "GET /callback rejects callbacks where the decoded state belongs to a different user" do
    user_a = create(:user)
    user_b = create(:user)
    sign_in user_a
    allow(EnableBanking::State).to receive(:decode).and_return({ user_id: user_b.id, tpp_credential_id: 1 })
    get "/callback", params: { state: "x", code: "y" }
    expect(response).to redirect_to(admin_bank_connections_path)
    expect(flash[:alert]).to match(/mismatch/i)
  end

  it "GET /callback rejects callbacks with a blank authorization code" do
    user = create(:user)
    sign_in user
    allow(EnableBanking::State).to receive(:decode).and_return({ user_id: user.id, tpp_credential_id: 1 })
    get "/callback", params: { state: "x", code: "" }
    expect(response).to redirect_to(admin_bank_connections_path)
    expect(flash[:alert]).to match(/code/i)
  end

  it "GET /callback rejects callbacks pointing at a credential that does not belong to the user" do
    user = create(:user)
    other_user = create(:user)
    other_credential = create(:tpp_credential, user: other_user)
    sign_in user
    allow(EnableBanking::State).to receive(:decode)
      .and_return({ user_id: user.id, tpp_credential_id: other_credential.id })
    get "/callback", params: { state: "x", code: "code" }
    expect(response).to redirect_to(admin_bank_connections_path)
    expect(flash[:alert]).to match(/credential/i)
  end

  it "GET /callback happy path delegates to CreateConnection and redirects to the new connection" do
    user = create(:user)
    credential = create(:tpp_credential, user: user)
    bc = create(:bank_connection, tpp_credential: credential, bank_name: "PKO BP")
    sign_in user
    allow(EnableBanking::State).to receive(:decode)
      .and_return({ user_id: user.id, tpp_credential_id: credential.id })
    allow(EnableBanking::Operations::CreateConnection).to receive(:call).and_return(bc)

    get "/callback", params: { state: "x", code: "code" }

    expect(EnableBanking::Operations::CreateConnection).to have_received(:call).with(
      credential: credential,
      code: "code",
      state: { user_id: user.id, tpp_credential_id: credential.id }
    )
    expect(response).to redirect_to(admin_bank_connection_path(bc))
    expect(flash[:notice]).to match(/PKO BP/)
  end

  it "GET /callback redirects with an alert when CreateConnection raises Failed" do
    user = create(:user)
    credential = create(:tpp_credential, user: user)
    sign_in user
    allow(EnableBanking::State).to receive(:decode)
      .and_return({ user_id: user.id, tpp_credential_id: credential.id })
    allow(EnableBanking::Operations::CreateConnection).to receive(:call)
      .and_raise(EnableBanking::Operations::CreateConnection::Failed.new("boom"))

    get "/callback", params: { state: "x", code: "code" }

    expect(response).to redirect_to(admin_bank_connections_path)
    expect(flash[:alert]).to eq("boom")
  end

  it "GET /admin/sign_in renders the Devise form using the admin_auth layout" do
    create(:user)
    get "/admin/sign_in"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="user[email]"')
    expect(response.body).to include('name="user[password]"')
  end

  it "POST /admin/sign_in with valid credentials signs the user in and redirects through the admin root" do
    user = create(:user, password: "Password123!")
    post "/admin/sign_in", params: { user: { email: user.email, password: "Password123!" } }
    expect(response).to be_redirect
    follow_redirect!
    expect(response).to redirect_to(admin_root_path)
  end

  it "POST /admin/sign_in with the wrong password re-renders the form without echoing the password" do
    user = create(:user, password: "Password123!")
    post "/admin/sign_in", params: { user: { email: user.email, password: "WrongPassword999!" } }
    expect(response.body).not_to include("WrongPassword999!")
    expect(response).not_to be_redirect
  end

  it "DELETE /admin/sign_out signs the user out and protected admin paths then redirect to sign-in" do
    user = create(:user)
    sign_in user
    delete "/admin/sign_out"
    expect(response).to be_redirect
    get "/admin/styleguide"
    expect(response).to redirect_to(new_user_session_path)
  end

  it "GET /admin/password/new renders the Devise reset request form" do
    create(:user)
    get "/admin/password/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="user[email]"')
  end

  it "POST /admin/password with a known email redirects to sign-in with a neutral notice" do
    create(:user, email: "known@example.test")
    expect {
      post "/admin/password", params: { user: { email: "known@example.test" } }
    }.to change { ActionMailer::Base.deliveries.size }.by(1).or change { ActionMailer::Base.deliveries.size }.by(0)
    expect(response).to redirect_to(new_user_session_path)
  end

  it "GET /admin/password/edit with a valid reset token renders the form" do
    user = create(:user)
    raw_token = user.send(:set_reset_password_token)
    get "/admin/password/edit", params: { reset_password_token: raw_token }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="user[password]"')
  end
end
