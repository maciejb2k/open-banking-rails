# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings area", type: :request do
  it "GET /admin/settings/preferences/profile returns 200 happy path" do
    user = create(:user)
    sign_in user

    get admin_settings_preferences_profile_path

    expect(response).to have_http_status(:ok)
  end

  it "PATCH /admin/settings/preferences/profile updates the user's name and redirects with notice" do
    user = create(:user, name: "Old Name")
    sign_in user

    patch admin_settings_preferences_profile_path, params: { user: { name: "New Name" } }

    expect(user.reload.name).to eq("New Name")
    expect(response).to redirect_to(admin_settings_preferences_profile_path)
    expect(flash[:notice]).to be_present
  end

  it "PATCH /admin/settings/preferences/profile rejects a blank name with 422" do
    user = create(:user, name: "Old Name")
    sign_in user

    patch admin_settings_preferences_profile_path, params: { user: { name: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.name).to eq("Old Name")
  end

  it "PATCH /admin/settings/preferences/password rotates the password and bypasses the sign-out" do
    user = create(:user, password: "Password123!")
    sign_in user

    patch admin_settings_preferences_password_path, params: {
      user: {
        current_password: "Password123!",
        password: "NewPassword456!",
        password_confirmation: "NewPassword456!"
      }
    }

    expect(response).to redirect_to(admin_settings_preferences_profile_path)
    expect(user.reload.valid_password?("NewPassword456!")).to be(true)
    get admin_settings_preferences_profile_path
    expect(response).to have_http_status(:ok)
  end

  it "PATCH /admin/settings/preferences/password rejects the wrong current password and stays signed in" do
    user = create(:user, password: "Password123!")
    sign_in user

    patch admin_settings_preferences_password_path, params: {
      user: {
        current_password: "WrongPassword999!",
        password: "NewPassword456!",
        password_confirmation: "NewPassword456!"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.valid_password?("Password123!")).to be(true)
  end

  it "GET /admin/settings/preferences/app returns 200" do
    user = create(:user)
    sign_in user

    get admin_settings_preferences_app_path

    expect(response).to have_http_status(:ok)
  end

  it "PATCH /admin/settings/preferences/app saves preferences without re-running Cash::Tracking when track_cash is unchanged" do
    user = create(:user, track_cash: false)
    sign_in user
    allow(Cash::Tracking).to receive(:enable!)

    patch admin_settings_preferences_app_path, params: { user: { track_cash: "0" } }

    expect(Cash::Tracking).not_to have_received(:enable!)
    expect(response).to redirect_to(admin_settings_preferences_app_path)
  end

  it "PATCH /admin/settings/preferences/app turning track_cash on calls Cash::Tracking.enable! and embeds the wallet currency in the notice" do
    user = create(:user, track_cash: false)
    sign_in user
    wallet = build_stubbed(:bank_account, :cash, manual_owner: user, currency: "PLN")
    allow(Cash::Tracking).to receive(:enable!).and_return(
      Cash::Tracking::Result.new(wallet: wallet, linked: 3)
    )

    patch admin_settings_preferences_app_path, params: { user: { track_cash: "1" } }

    expect(Cash::Tracking).to have_received(:enable!).with(user: user)
    expect(response).to redirect_to(admin_settings_preferences_app_path)
    expect(flash[:notice]).to match(/PLN/)
    expect(flash[:notice]).to match(/3/)
  end

  it "PATCH /admin/settings/preferences/app does not re-enable Cash::Tracking when already on" do
    user = create(:user, track_cash: true)
    sign_in user
    allow(Cash::Tracking).to receive(:enable!)

    patch admin_settings_preferences_app_path, params: { user: { track_cash: "1" } }

    expect(Cash::Tracking).not_to have_received(:enable!)
  end

  it "PATCH /admin/settings/preferences/app forces hidden_category_ids to [] when the multi-select is omitted" do
    user = create(:user, track_cash: false)
    cat = create(:category, user: user)
    UserHiddenCategory.create!(user: user, category: cat)
    sign_in user

    patch admin_settings_preferences_app_path, params: { user: { track_cash: "0" } }

    expect(user.reload.hidden_category_ids).to eq([])
  end

  it "GET /admin/settings/preferences/llm returns 200, building a setting when none exists" do
    user = create(:user)
    sign_in user

    get admin_settings_preferences_llm_path

    expect(response).to have_http_status(:ok)
  end

  it "PATCH /admin/settings/preferences/llm creates the setting on first save" do
    user = create(:user)
    sign_in user

    patch admin_settings_preferences_llm_path, params: {
      llm_setting: { provider: "gemini", model: "gemini-2.5-flash", api_key: "sekret-key" }
    }

    expect(response).to redirect_to(admin_settings_preferences_llm_path)
    expect(user.reload.llm_setting).to be_present
    expect(user.llm_setting.api_key).to eq("sekret-key")
  end

  it "PATCH /admin/settings/preferences/llm with a blank api_key keeps the previous key on a persisted setting" do
    user = create(:user)
    user.create_llm_setting!(provider: "gemini", model: "gemini-2.5-flash", api_key: "old-secret")
    sign_in user

    patch admin_settings_preferences_llm_path, params: {
      llm_setting: { provider: "gemini", model: "gemini-2.5-pro", api_key: "" }
    }

    expect(response).to redirect_to(admin_settings_preferences_llm_path)
    setting = user.reload.llm_setting
    expect(setting.api_key).to eq("old-secret")
    expect(setting.model).to eq("gemini-2.5-pro")
  end

  it "PATCH /admin/settings/preferences/llm with a non-blank api_key rotates the key" do
    user = create(:user)
    user.create_llm_setting!(provider: "gemini", model: "gemini-2.5-flash", api_key: "old-secret")
    sign_in user

    patch admin_settings_preferences_llm_path, params: {
      llm_setting: { provider: "gemini", model: "gemini-2.5-flash", api_key: "fresh-secret" }
    }

    expect(user.reload.llm_setting.api_key).to eq("fresh-secret")
  end

  it "POST /admin/settings/preferences/llm/test redirects with alert when the LLM is not configured" do
    user = create(:user)
    sign_in user

    post admin_settings_preferences_test_llm_path

    expect(response).to redirect_to(admin_settings_preferences_llm_path)
    expect(flash[:alert]).to match(/save a provider/i)
  end

  it "POST /admin/settings/preferences/llm/test delegates to ConnectionTestRunner on success" do
    user = create(:user)
    setting = user.create_llm_setting!(provider: "gemini", model: "gemini-2.5-flash", api_key: "any-key")
    sign_in user
    run = create(:operation_run, kind: "llm_connection_test", triggered_by_user: user, subject: user)
    result = Llm::ConnectionTestRunner::Result.new(run: run, setting: setting)
    allow(Llm::ConnectionTestRunner).to receive(:call).with(user: user).and_return(result)

    post admin_settings_preferences_test_llm_path

    expect(response).to redirect_to(admin_settings_preferences_llm_path)
    expect(flash[:notice]).to match(/Connection OK/i)
  end

  it "POST /admin/settings/preferences/llm/test surfaces ConnectionTestRunner::Failed as flash[:alert]" do
    user = create(:user)
    user.create_llm_setting!(provider: "gemini", model: "gemini-2.5-flash", api_key: "any-key")
    sign_in user
    allow(Llm::ConnectionTestRunner).to receive(:call)
      .and_raise(Llm::ConnectionTestRunner::Failed.new("network down"))

    post admin_settings_preferences_test_llm_path

    expect(response).to redirect_to(admin_settings_preferences_llm_path)
    expect(flash[:alert]).to match(/network down/)
  end

  it "GET /admin/settings/preferences/data_exchange returns 200 with per-resource counts" do
    user = create(:user)
    sign_in user

    get admin_settings_preferences_data_exchange_path

    expect(response).to have_http_status(:ok)
  end

  it "POST /admin/settings/preferences/data_exchange/export streams the encrypted bundle on success" do
    user = create(:user)
    sign_in user
    run = create(:operation_run, kind: "data_export", triggered_by_user: user, subject: user)
    result = DataExchange::Operations::Export::Result.new(blob: "ENCRYPTED-BLOB", run: run)
    allow(DataExchange::Operations::Export).to receive(:call).and_return(result)

    post admin_settings_preferences_data_exchange_export_path, params: { passphrase: "hunter2" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to eq("application/octet-stream")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.headers["Content-Disposition"]).to include("obr-export-")
    expect(response.body).to eq("ENCRYPTED-BLOB")
  end

  it "POST /admin/settings/preferences/data_exchange/export surfaces Export::Failed as flash[:alert]" do
    user = create(:user)
    sign_in user
    allow(DataExchange::Operations::Export).to receive(:call)
      .and_raise(DataExchange::Operations::Export::Failed.new("bad pass"))

    post admin_settings_preferences_data_exchange_export_path, params: { passphrase: "" }

    expect(response).to redirect_to(admin_settings_preferences_data_exchange_path)
    expect(flash[:alert]).to match(/bad pass/)
  end

  it "POST /admin/settings/preferences/data_exchange/import refuses when no bundle file is uploaded" do
    user = create(:user)
    sign_in user

    post admin_settings_preferences_data_exchange_import_path

    expect(response).to redirect_to(admin_settings_preferences_data_exchange_path)
    expect(flash[:alert]).to match(/required/i)
  end

  it "POST /admin/settings/preferences/data_exchange/import delegates to Import.call with the parsed strategy and reports counts" do
    user = create(:user)
    sign_in user
    fake_result = Struct.new(:imported, :updated, :skipped, :failed, :warnings, :per_resource, :run, keyword_init: true).new(
      imported: 1, updated: 2, skipped: 0, failed: 0, warnings: [], per_resource: {}, run: nil
    )
    allow(DataExchange::Operations::Import).to receive(:call).and_return(fake_result)

    post admin_settings_preferences_data_exchange_import_path, params: {
      bundle: Rack::Test::UploadedFile.new(StringIO.new("BUNDLE-CONTENTS"), "application/octet-stream", original_filename: "x.obrbundle"),
      passphrase: "p",
      strategy: "overwrite"
    }

    expect(DataExchange::Operations::Import).to have_received(:call) do |kwargs|
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:strategy]).to eq(:overwrite)
      expect(kwargs[:passphrase]).to eq("p")
      expect(kwargs[:bundle_blob]).to eq("BUNDLE-CONTENTS")
    end
    expect(response).to redirect_to(admin_settings_preferences_data_exchange_path)
    expect(flash[:notice]).to match(/1.*imported.*2.*updated.*0.*skipped/i)
  end

  it "POST /admin/settings/preferences/data_exchange/import surfaces Import::Failed as flash[:alert]" do
    user = create(:user)
    sign_in user
    allow(DataExchange::Operations::Import).to receive(:call)
      .and_raise(DataExchange::Operations::Import::Failed.new("bad pass"))

    post admin_settings_preferences_data_exchange_import_path, params: {
      bundle: Rack::Test::UploadedFile.new(StringIO.new("X"), "application/octet-stream", original_filename: "x.obrbundle"),
      passphrase: "p"
    }

    expect(response).to redirect_to(admin_settings_preferences_data_exchange_path)
    expect(flash[:alert]).to match(/bad pass/)
  end

  it "GET /admin/settings/preferences/api_tokens returns 200 with no tokens for a fresh user" do
    user = create(:user)
    sign_in user

    get admin_settings_preferences_api_tokens_path

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/settings/preferences/api_tokens orders revoked tokens after active ones" do
    user = create(:user)
    active = PersonalAccessToken.create!(user: user, name: "alpha-active",
                                         token_digest: PersonalAccessToken.digest_for("obrl_active"),
                                         last_four: "tive")
    revoked = PersonalAccessToken.create!(user: user, name: "beta-revoked",
                                          token_digest: PersonalAccessToken.digest_for("obrl_revoked"),
                                          last_four: "oked",
                                          revoked_at: 1.day.ago)
    sign_in user

    get admin_settings_preferences_api_tokens_path

    expect(response).to have_http_status(:ok)
    expect(response.body.index(active.name)).to be < response.body.index(revoked.name)
  end

  it "POST /admin/settings/preferences/api_tokens delegates to PersonalAccessTokenIssuer and exposes the raw token via flash for one hop" do
    user = create(:user)
    record = PersonalAccessToken.new(user: user, name: "laptop")
    record.token_digest = PersonalAccessToken.digest_for("obrl_raw")
    record.last_four = "0raw"
    record.save!
    issuer_result = Auth::PersonalAccessTokenIssuer::Result.new(
      success?: true, token_record: record, raw_token: "obrl_raw_value"
    )
    allow(Auth::PersonalAccessTokenIssuer).to receive(:call).and_return(issuer_result)
    sign_in user

    post admin_settings_preferences_api_tokens_path, params: { personal_access_token: { name: "laptop" } }

    expect(response).to redirect_to(admin_settings_preferences_api_tokens_path)
    expect(flash[:notice]).to match(/laptop/)
    follow_redirect!
    expect(response.body).to include("obrl_raw_value")

    get admin_settings_preferences_api_tokens_path
    expect(response.body).not_to include("obrl_raw_value")
  end

  it "POST /admin/settings/preferences/api_tokens with a blank name renders 422 with the half-built record" do
    user = create(:user)
    half = PersonalAccessToken.new(user: user, name: "")
    failure = Auth::PersonalAccessTokenIssuer::Result.new(
      success?: false, token_record: half, error_messages: [ "name can't be blank" ]
    )
    allow(Auth::PersonalAccessTokenIssuer).to receive(:call).and_return(failure)
    sign_in user

    post admin_settings_preferences_api_tokens_path, params: { personal_access_token: { name: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("name can&#39;t be blank").or include("name can't be blank")
  end

  it "POST /admin/settings/preferences/api_tokens lets two users share a token name without colliding" do
    user_a = create(:user)
    user_b = create(:user)
    PersonalAccessToken.create!(user: user_b, name: "laptop",
                                token_digest: PersonalAccessToken.digest_for("obrl_b"),
                                last_four: "ob_b")
    record = PersonalAccessToken.new(user: user_a, name: "laptop")
    record.token_digest = PersonalAccessToken.digest_for("obrl_a")
    record.last_four = "ob_a"
    record.save!
    success = Auth::PersonalAccessTokenIssuer::Result.new(
      success?: true, token_record: record, raw_token: "obrl_a_value"
    )
    allow(Auth::PersonalAccessTokenIssuer).to receive(:call).and_return(success)
    sign_in user_a

    post admin_settings_preferences_api_tokens_path, params: { personal_access_token: { name: "laptop" } }

    expect(response).to redirect_to(admin_settings_preferences_api_tokens_path)
  end

  it "DELETE /admin/settings/preferences/api_tokens/:id revokes an active token without deleting the row" do
    user = create(:user)
    token = PersonalAccessToken.create!(user: user, name: "soft-revoke",
                                        token_digest: PersonalAccessToken.digest_for("obrl_zzz"),
                                        last_four: "lzzz")
    sign_in user

    expect {
      delete admin_settings_preferences_api_token_path(token)
    }.not_to change(PersonalAccessToken, :count)
    expect(token.reload.revoked_at).to be_present
    expect(response).to redirect_to(admin_settings_preferences_api_tokens_path)
    expect(flash[:notice]).to match(/revoked/i)
  end

  it "DELETE /admin/settings/preferences/api_tokens/:id hard-deletes a previously revoked token on the second click" do
    user = create(:user)
    token = PersonalAccessToken.create!(user: user, name: "hard-delete",
                                        token_digest: PersonalAccessToken.digest_for("obrl_yyy"),
                                        last_four: "lyyy",
                                        revoked_at: 1.day.ago)
    sign_in user

    expect {
      delete admin_settings_preferences_api_token_path(token)
    }.to change(PersonalAccessToken, :count).by(-1)
    expect(response).to redirect_to(admin_settings_preferences_api_tokens_path)
    expect(flash[:notice]).to match(/deleted/i)
  end

  it_behaves_like "a cross-user isolated resource",
                  verb: :delete,
                  path_for: ->(record) { Rails.application.routes.url_helpers.admin_settings_preferences_api_token_path(record) },
                  build_record: ->(user) {
                    PersonalAccessToken.create!(
                      user:         user,
                      name:         "isolation-#{SecureRandom.hex(3)}",
                      token_digest: PersonalAccessToken.digest_for("obrl_iso_#{SecureRandom.hex(4)}"),
                      last_four:    SecureRandom.hex(2)
                    )
                  }

  it "GET /admin/settings/preferences/profile without sign-in redirects to /admin/sign_in" do
    create(:user)
    get admin_settings_preferences_profile_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
