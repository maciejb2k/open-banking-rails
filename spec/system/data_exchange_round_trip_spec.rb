# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Data exchange round trip journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "renders per-resource counts on the data-exchange page once the user has TPP credentials, connections, and accounts" do
    user = build_seeded_data_exchange_user(name: "Counter")

    sign_in_via_form(user)

    visit admin_settings_preferences_data_exchange_path
    expect(page).to have_text("Export")
    expect(page).to have_text("Tpp credentials")
    expect(page).to have_text("Bank connections")
    expect(page).to have_text("Bank accounts")
    expect(page).to have_text("1 record")
  end

  it "downloads a passphrase-encrypted bundle on export submission and records a succeeded data_export OperationRun" do
    user = build_seeded_data_exchange_user(name: "Exporter")

    sign_in_via_form(user)
    visit admin_settings_preferences_data_exchange_path

    within("form[action='#{admin_settings_preferences_data_exchange_export_path}']") do
      fill_in "passphrase", with: "round-trip-pass-1234"
      click_button "Download bundle"
    end

    expect(page.response_headers["Content-Type"]).to eq("application/octet-stream")
    expect(page.response_headers["Content-Disposition"]).to include("attachment")
    expect(page.response_headers["Content-Disposition"]).to include("obr-export-")
    expect(page.body.bytesize).to be > 0

    run = OperationRun.where(triggered_by_user_id: user.id, kind: "data_export").order(:id).last
    expect(run).to be_present
    expect(run.status).to eq("succeeded")
    expect(run.summary["counts"]).to include("tpp_credentials" => 1, "bank_connections" => 1, "bank_accounts" => 1)
  end

  it "round-trips a full export → wipe → import for the same user, restoring TPP credential, bank connection, and account natural keys" do
    user = build_seeded_data_exchange_user(name: "Round Tripper")

    export_result = DataExchange::Operations::Export.call(
      user:          user,
      resource_keys: DataExchange::Registry.all_keys,
      passphrase:    "round-trip-pass-1234"
    )
    expect(export_result.run.status).to eq("succeeded")
    bundle_path = write_bundle_to_disk(export_result.blob)

    BankAccount.where(tpp_credential_id: user.tpp_credentials.select(:id)).delete_all
    BankConnection.where(tpp_credential_id: user.tpp_credentials.select(:id)).delete_all
    user.tpp_credentials.delete_all
    expect(user.reload.tpp_credentials.count).to eq(0)

    sign_in_via_form(user)
    visit admin_settings_preferences_data_exchange_path
    within("form[action='#{admin_settings_preferences_data_exchange_import_path}']") do
      attach_file "bundle", bundle_path
      fill_in "passphrase", with: "round-trip-pass-1234"
      choose "strategy_skip_existing"
      click_button "Import bundle"
    end

    expect(page).to have_current_path(admin_settings_preferences_data_exchange_path, ignore_query: true)
    expect(page).to have_text(/imported/i)

    user.reload
    expect(user.tpp_credentials.where(name: "Round Tripper TPP").count).to eq(1)
    expect(user.tpp_credentials.first.bank_connections.where(bank_slug: "round_tripper_bank").count).to eq(1)
    imported_account = BankAccount.find_by(uid: "round-trip-uid-1")
    expect(imported_account).to be_present
    expect(imported_account.name).to eq("Round Tripper Account")
    expect(imported_account.currency).to eq("PLN")
    expect(imported_account.tpp_credential.user).to eq(user)

    import_run = OperationRun.where(triggered_by_user_id: user.id, kind: "data_import").order(:id).last
    expect(import_run).to be_present
    expect(import_run.status).to eq("succeeded")
  end

  it "rejects an import with the wrong passphrase, surfaces the failure as a flash alert, and writes nothing to the database" do
    user = build_seeded_data_exchange_user(name: "Wrong Pass")

    export_result = DataExchange::Operations::Export.call(
      user:          user,
      resource_keys: DataExchange::Registry.all_keys,
      passphrase:    "right-pass"
    )
    bundle_path = write_bundle_to_disk(export_result.blob)

    counts_before = {
      tpp:     user.tpp_credentials.count,
      conn:    BankConnection.where(tpp_credential_id: user.tpp_credentials.select(:id)).count,
      account: BankAccount.where(tpp_credential_id: user.tpp_credentials.select(:id)).count,
      runs:    OperationRun.where(triggered_by_user_id: user.id, kind: "data_import").count
    }

    sign_in_via_form(user)
    visit admin_settings_preferences_data_exchange_path
    within("form[action='#{admin_settings_preferences_data_exchange_import_path}']") do
      attach_file "bundle", bundle_path
      fill_in "passphrase", with: "wrong-pass"
      click_button "Import bundle"
    end

    expect(page).to have_current_path(admin_settings_preferences_data_exchange_path, ignore_query: true)
    expect(page).to have_text(/import failed/i)

    expect(user.reload.tpp_credentials.count).to eq(counts_before[:tpp])
    expect(BankConnection.where(tpp_credential_id: user.tpp_credentials.select(:id)).count).to eq(counts_before[:conn])
    expect(BankAccount.where(tpp_credential_id: user.tpp_credentials.select(:id)).count).to eq(counts_before[:account])
    expect(OperationRun.where(triggered_by_user_id: user.id, kind: "data_import").count).to eq(counts_before[:runs])
  end

  it "rejects an import with a malformed bundle blob via the Import::Failed flash alert" do
    user = build_seeded_data_exchange_user(name: "Malformed")
    bad_bundle = write_bundle_to_disk("totally-not-a-valid-encrypted-bundle")

    sign_in_via_form(user)
    visit admin_settings_preferences_data_exchange_path
    within("form[action='#{admin_settings_preferences_data_exchange_import_path}']") do
      attach_file "bundle", bad_bundle
      fill_in "passphrase", with: "anything"
      click_button "Import bundle"
    end

    expect(page).to have_current_path(admin_settings_preferences_data_exchange_path, ignore_query: true)
    expect(page).to have_text(/import failed/i)
  end

  def build_seeded_data_exchange_user(name:)
    user = User.create!(
      email:    "exchange-#{SecureRandom.hex(4)}@example.test",
      password: "Password123!",
      name:     name
    )
    credential = user.tpp_credentials.create!(
      name:            "#{name} TPP",
      provider:        "enable_banking",
      environment:     "SANDBOX",
      status:          "active",
      primary:         true,
      application_id:  "fake-app-#{SecureRandom.hex(4)}",
      redirect_url:    "http://localhost:3000/admin/oauth/enable_banking/callback",
      private_key_pem: "fake-pem"
    )
    connection = credential.bank_connections.create!(
      bank_slug:           "#{name.parameterize(separator: '_')}_bank",
      bank_country:        "PL",
      bank_name:           "#{name} Bank",
      status:              "authorized",
      psu_type:            "personal",
      session_id:          "sess-#{SecureRandom.hex(4)}",
      valid_until:         30.days.from_now,
      authorized_at:       Time.current,
      access_balances:     true,
      access_transactions: true
    )
    BankAccount.create!(
      uid:                     "round-trip-uid-1",
      iban:                    "PL61109010140000071219#{format('%06d', user.id)}",
      currency:                "PLN",
      name:                    "#{name} Account",
      product:                 "Personal",
      cash_account_type:       "CACC",
      status:                  "active",
      tpp_credential:          credential,
      current_bank_connection: connection,
      all_account_ids:         []
    )
    user
  end

  def sign_in_via_form(user)
    visit "/admin/sign_in"
    fill_in "user[email]",    with: user.email
    fill_in "user[password]", with: "Password123!"
    click_button "Sign in"
  end

  def write_bundle_to_disk(blob)
    path = Rails.root.join("tmp", "spec-bundle-#{SecureRandom.hex(8)}.obrbundle")
    File.binwrite(path, blob)
    path.to_s
  end
end
