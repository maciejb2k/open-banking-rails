# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Banking area", type: :request do
  it "GET /admin/tpp_credentials returns 200 with only the current user's credentials" do
    user = create(:user)
    other = create(:user)
    own_credential = create(:tpp_credential, user: user, name: "Mine")
    other_credential = create(:tpp_credential, user: other, name: "Theirs")
    sign_in user

    get admin_tpp_credentials_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_credential.name)
    expect(response.body).not_to include(other_credential.name)
  end

  it_behaves_like "a cross-user isolated resource",
                  verb: :get,
                  path_for: ->(record) { Rails.application.routes.url_helpers.admin_tpp_credential_path(record) },
                  build_record: ->(user) { create(:tpp_credential, user: user) }

  it "GET /admin/tpp_credentials/new builds a form with the enable_banking provider default" do
    user = create(:user)
    sign_in user

    get new_admin_tpp_credential_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("enable_banking")
  end

  it "POST /admin/tpp_credentials makes the first credential primary automatically" do
    user = create(:user)
    sign_in user

    post admin_tpp_credentials_path, params: {
      tpp_credential: {
        name: "First", provider: "enable_banking", environment: "SANDBOX",
        redirect_url: "http://localhost:3000/callback",
        application_id: "app-1",
        private_key_pem: OpenSSL::PKey::RSA.new(2048).to_pem,
        public_cert_pem: ""
      }
    }

    created = user.tpp_credentials.find_by(name: "First")
    expect(created).to be_present
    expect(created.primary?).to be(true)
    expect(response).to redirect_to(admin_tpp_credential_path(created))
  end

  it "POST /admin/tpp_credentials does not auto-mark a second credential as primary" do
    user = create(:user)
    create(:tpp_credential, user: user, primary: true)
    sign_in user

    post admin_tpp_credentials_path, params: {
      tpp_credential: {
        name: "Second", provider: "enable_banking", environment: "SANDBOX",
        redirect_url: "http://localhost:3000/callback",
        application_id: "app-2",
        private_key_pem: OpenSSL::PKey::RSA.new(2048).to_pem,
        public_cert_pem: ""
      }
    }

    second = user.tpp_credentials.find_by(name: "Second")
    expect(second).to be_present
    expect(second.primary?).to be(false)
  end

  it "POST /admin/tpp_credentials with missing required fields renders :new with 422" do
    user = create(:user)
    sign_in user

    post admin_tpp_credentials_path, params: {
      tpp_credential: { name: "" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.tpp_credentials.count).to eq(0)
  end

  it "DELETE /admin/tpp_credentials/:id refuses when bank connections still reference it" do
    user = create(:user)
    credential = create(:tpp_credential, user: user)
    create(:bank_connection, tpp_credential: credential)
    sign_in user

    expect {
      delete admin_tpp_credential_path(credential)
    }.not_to change(TppCredential, :count)
    expect(response).to redirect_to(admin_tpp_credential_path(credential))
    expect(flash[:alert]).to match(/connections/i)
  end

  it "DELETE /admin/tpp_credentials/:id destroys an unreferenced credential" do
    user = create(:user)
    credential = create(:tpp_credential, user: user)
    sign_in user

    expect {
      delete admin_tpp_credential_path(credential)
    }.to change { user.tpp_credentials.count }.by(-1)
    expect(response).to redirect_to(admin_tpp_credentials_path)
  end

  it "POST /admin/tpp_credentials/:id/test_connection delegates to VerifyCredential and renders its message as notice on success" do
    user = create(:user)
    credential = create(:tpp_credential, user: user)
    sign_in user
    ok_result = EnableBanking::Operations::VerifyCredential::VerifyResult.new(
      status: :ok, message: "Connection verified."
    )
    allow(EnableBanking::Operations::VerifyCredential).to receive(:call).with(credential).and_return(ok_result)

    post test_connection_admin_tpp_credential_path(credential)

    expect(response).to redirect_to(admin_tpp_credential_path(credential))
    expect(flash[:notice]).to eq("Connection verified.")
  end

  it "POST /admin/tpp_credentials/:id/test_connection routes a failed result to flash[:alert]" do
    user = create(:user)
    credential = create(:tpp_credential, user: user)
    sign_in user
    failed = EnableBanking::Operations::VerifyCredential::VerifyResult.new(
      status: :failed, message: "Test failed: boom"
    )
    allow(EnableBanking::Operations::VerifyCredential).to receive(:call).and_return(failed)

    post test_connection_admin_tpp_credential_path(credential)

    expect(flash[:alert]).to eq("Test failed: boom")
  end

  it "POST /admin/tpp_credentials/:id/make_primary calls the model and redirects with notice" do
    user = create(:user)
    a = create(:tpp_credential, user: user, primary: true, name: "Old primary")
    b = create(:tpp_credential, user: user, primary: false, name: "New primary")
    sign_in user

    post make_primary_admin_tpp_credential_path(b)

    expect(response).to redirect_to(admin_tpp_credential_path(b))
    expect(b.reload.primary?).to be(true)
    expect(a.reload.primary?).to be(false)
  end

  it "GET /admin/bank_connections lists only the current user's connections" do
    user = create(:user)
    other = create(:user)
    own = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user), bank_name: "PKO BP")
    foreign = create(:bank_connection, tpp_credential: create(:tpp_credential, user: other), bank_name: "MTHEIR BANK")
    sign_in user

    get admin_bank_connections_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own.bank_name)
    expect(response.body).not_to include(foreign.bank_name)
  end

  it_behaves_like "a cross-user isolated resource",
                  verb: :get,
                  path_for: ->(record) { Rails.application.routes.url_helpers.admin_bank_connection_path(record) },
                  build_record: ->(user) { create(:bank_connection, tpp_credential: create(:tpp_credential, user: user)) }

  it "GET /admin/bank_connections/new redirects to credentials when no primary credential exists" do
    user = create(:user)
    sign_in user

    get new_admin_bank_connection_path

    expect(response).to redirect_to(admin_tpp_credentials_path)
    expect(flash[:alert]).to match(/primary/i)
  end

  it "GET /admin/bank_connections/new with a primary credential lists ASPSPs sorted by name" do
    user = create(:user)
    create(:tpp_credential, user: user, primary: true)
    sign_in user
    list = EnableBanking::Result.new(
      success: true, status: 200,
      data: { "aspsps" => [ { "name" => "Z Bank" }, { "name" => "A Bank" } ] },
      headers: {}, error: nil
    )
    allow(EnableBanking::Api::ListAspsps).to receive(:call).and_return(list)

    get new_admin_bank_connection_path

    expect(response).to have_http_status(:ok)
    expect(response.body.index("A Bank")).to be < response.body.index("Z Bank")
  end

  it "GET /admin/bank_connections/new redirects to index with an alert when ListAspsps fails" do
    user = create(:user)
    create(:tpp_credential, user: user, primary: true)
    sign_in user
    failure = EnableBanking::Result.new(success: false, status: 500, data: nil, headers: {}, error: "boom")
    allow(EnableBanking::Api::ListAspsps).to receive(:call).and_return(failure)

    get new_admin_bank_connection_path

    expect(response).to redirect_to(admin_bank_connections_path)
    expect(flash[:alert]).to match(/boom/)
  end

  it "GET /admin/bank_connections/new ignores a `replaces` query param pointing at another user's connection" do
    user = create(:user)
    create(:tpp_credential, user: user, primary: true)
    other = create(:user)
    foreign = create(:bank_connection, tpp_credential: create(:tpp_credential, user: other))
    list = EnableBanking::Result.new(success: true, status: 200, data: { "aspsps" => [] }, headers: {}, error: nil)
    allow(EnableBanking::Api::ListAspsps).to receive(:call).and_return(list)
    sign_in user

    get new_admin_bank_connection_path, params: { replaces: foreign.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(%(name="replaces_connection_id" value="#{foreign.id}"))
  end

  it "POST /admin/bank_connections happy path redirects off-host to the bank auth URL with status 303" do
    user = create(:user)
    create(:tpp_credential, user: user, primary: true)
    sign_in user
    allow(EnableBanking::Operations::StartAuth).to receive(:call).and_return("https://bank.example/auth?session=1")

    post admin_bank_connections_path, params: {
      bank_connection_request_form: {
        aspsp_name: "PKO BP", aspsp_country: "PL", psu_type: "personal", valid_days: 90
      }
    }

    expect(response).to have_http_status(:see_other)
    expect(response.location).to eq("https://bank.example/auth?session=1")
  end

  it "POST /admin/bank_connections rescues StartAuth::Failed and redirects with the exception message" do
    user = create(:user)
    create(:tpp_credential, user: user, primary: true)
    sign_in user
    list = EnableBanking::Result.new(success: true, status: 200, data: { "aspsps" => [] }, headers: {}, error: nil)
    allow(EnableBanking::Api::ListAspsps).to receive(:call).and_return(list)
    allow(EnableBanking::Operations::StartAuth).to receive(:call)
      .and_raise(EnableBanking::Operations::StartAuth::Failed.new("auth blew up"))

    post admin_bank_connections_path, params: {
      bank_connection_request_form: {
        aspsp_name: "PKO BP", aspsp_country: "PL", psu_type: "personal", valid_days: 90
      }
    }

    expect(response).to redirect_to(new_admin_bank_connection_path)
    expect(flash[:alert]).to eq("auth blew up")
  end

  it "DELETE /admin/bank_connections/:id delegates to CloseConnection and redirects to index" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user))
    sign_in user
    allow(EnableBanking::Operations::CloseConnection).to receive(:call)

    delete admin_bank_connection_path(connection)

    expect(EnableBanking::Operations::CloseConnection).to have_received(:call).with(connection)
    expect(response).to redirect_to(admin_bank_connections_path)
    expect(flash[:notice]).to be_present
  end

  it "POST /admin/bank_connections/:id/refresh delegates to RefreshConnection and surfaces failures as alerts" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user))
    sign_in user
    allow(EnableBanking::Operations::RefreshConnection).to receive(:call)
      .and_raise(EnableBanking::Operations::RefreshConnection::Failed.new("HTTP 500"))

    post refresh_admin_bank_connection_path(connection)

    expect(response).to redirect_to(admin_bank_connection_path(connection))
    expect(flash[:alert]).to match(/HTTP 500/)
  end

  it "POST /admin/bank_connections/:id/reauth redirects to /new with all bank params and a notice" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user),
                                          bank_name: "PKO BP", bank_country: "PL", psu_type: "personal")
    sign_in user

    post reauth_admin_bank_connection_path(connection)

    expect(response.location).to include("aspsp_name=PKO+BP")
    expect(response.location).to include("aspsp_country=PL")
    expect(response.location).to include("psu_type=personal")
    expect(response.location).to include("replaces=#{connection.id}")
    expect(flash[:notice]).to match(/re-authorize/i)
  end

  it "GET /admin/bank_accounts lists only accounts under the current user's TPP credentials" do
    user = create(:user)
    other = create(:user)
    own_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user), name: "Mine PLN")
    foreign_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: other), name: "Foreign Account XYZ")
    sign_in user

    get admin_bank_accounts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_account.name)
    expect(response.body).not_to include(foreign_account.name)
  end

  it "GET /admin/bank_accounts/:id returns 404 when accessed via another user's TPP credential" do
    user = create(:user)
    other = create(:user)
    foreign_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: other))
    sign_in user

    get admin_bank_account_path(foreign_account)

    expect(response).to have_http_status(:not_found)
  end

  it "POST /admin/bank_accounts/:id/refresh_details delegates to RefreshAccountDetails and surfaces failure as alert" do
    user = create(:user)
    account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    sign_in user
    allow(EnableBanking::Operations::RefreshAccountDetails).to receive(:call)
      .and_raise(EnableBanking::Operations::RefreshAccountDetails::Failed.new("network down"))

    post refresh_details_admin_bank_account_path(account)

    expect(response).to redirect_to(admin_bank_account_path(account))
    expect(flash[:alert]).to match(/network down/)
  end

  it "POST /admin/bank_accounts/:id/refresh_balances delegates to RefreshAccountBalances on the happy path" do
    user = create(:user)
    account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    sign_in user
    allow(EnableBanking::Operations::RefreshAccountBalances).to receive(:call)

    post refresh_balances_admin_bank_account_path(account)

    expect(EnableBanking::Operations::RefreshAccountBalances).to have_received(:call).with(account)
    expect(response).to redirect_to(admin_bank_account_path(account))
    expect(flash[:notice]).to be_present
  end

  it "GET /admin/bank_transactions returns 200 listing only the current user's transactions" do
    user = create(:user)
    other = create(:user)
    own_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    foreign_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: other))
    own_tx = create(:bank_transaction, bank_account: own_account, title: "MINE TX 12345")
    foreign_tx = create(:bank_transaction, bank_account: foreign_account, title: "FOREIGN TX 99999")
    sign_in user

    get admin_bank_transactions_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_tx.title)
    expect(response.body).not_to include(foreign_tx.title)
  end

  it "GET /admin/bank_transactions accepts ransack sort params without raising" do
    user = create(:user)
    sign_in user

    get admin_bank_transactions_path, params: { q: { s: "booking_date asc" } }

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/bank_transactions/:id returns 404 for another user's transaction" do
    user = create(:user)
    other = create(:user)
    foreign_tx = create(:bank_transaction, bank_account: create(:bank_account, tpp_credential: create(:tpp_credential, user: other)))
    sign_in user

    get admin_bank_transaction_path(foreign_tx)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/transaction_syncs lists only operation runs triggered by the current user" do
    user = create(:user)
    other = create(:user)
    own_run = create(:operation_run, kind: "transaction_sync", triggered_by_user: user, subject: user)
    foreign_run = create(:operation_run, kind: "transaction_sync", triggered_by_user: other, subject: other)
    sign_in user

    get admin_transaction_syncs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_transaction_sync_path(own_run))
    expect(response.body).not_to include(admin_transaction_sync_path(foreign_run))
  end

  it "GET /admin/transaction_syncs/:id returns 404 when the run was triggered by another user" do
    user = create(:user)
    other = create(:user)
    foreign_run = create(:operation_run, kind: "transaction_sync", triggered_by_user: other, subject: other)
    sign_in user

    get admin_transaction_sync_path(foreign_run)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/transaction_syncs/new returns 200 listing only the current user's active connections" do
    user = create(:user)
    other = create(:user)
    own_conn = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user), bank_name: "MyBank-AAA", status: "authorized")
    create(:bank_connection, tpp_credential: create(:tpp_credential, user: other), bank_name: "TheirBank-XXX", status: "authorized")
    sign_in user

    get new_admin_transaction_sync_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_conn.bank_name)
    expect(response.body).not_to include("TheirBank-XXX")
  end

  it "POST /admin/transaction_syncs delegates to TransactionSyncs::Queuer with the params and redirects to the run on success" do
    user = create(:user)
    sign_in user
    run = create(:operation_run, kind: "transaction_sync", triggered_by_user: user, subject: user)
    success = TransactionSyncs::Queuer::Result.new(success?: true, run: run)
    allow(TransactionSyncs::Queuer).to receive(:call).and_return(success)

    post admin_transaction_syncs_path, params: { bank_connection_id: "", date_from: "", date_to: "" }

    expect(TransactionSyncs::Queuer).to have_received(:call) do |kwargs|
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:input]).to be_a(TransactionSyncs::Queuer::Input)
    end
    expect(response).to redirect_to(admin_transaction_sync_path(run))
    expect(flash[:notice]).to match(/queued/i)
  end

  it "POST /admin/transaction_syncs surfaces a failed Queuer Result as a flash alert" do
    user = create(:user)
    sign_in user
    failure = TransactionSyncs::Queuer::Result.new(success?: false, error_messages: [ "boom" ])
    allow(TransactionSyncs::Queuer).to receive(:call).and_return(failure)

    post admin_transaction_syncs_path, params: { bank_connection_id: "" }

    expect(response).to redirect_to(new_admin_transaction_sync_path)
    expect(flash[:alert]).to match(/boom/)
  end

  it "GET /admin/bank_connections/:bc_id/sync_schedule/edit renders the form with no SyncSchedule persisted yet" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user))
    sign_in user

    get edit_admin_bank_connection_sync_schedule_path(connection)

    expect(response).to have_http_status(:ok)
    expect(connection.reload.sync_schedule).to be_nil
  end

  it "GET /admin/bank_connections/:bc_id/sync_schedule/edit returns 404 for another user's connection" do
    user = create(:user)
    other = create(:user)
    foreign = create(:bank_connection, tpp_credential: create(:tpp_credential, user: other))
    sign_in user

    get edit_admin_bank_connection_sync_schedule_path(foreign)

    expect(response).to have_http_status(:not_found)
  end

  it "PATCH /admin/bank_connections/:bc_id/sync_schedule delegates to ScheduleUpserter on the happy path" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user))
    sign_in user
    schedule = SyncSchedule.new(bank_connection: connection, enabled: true, cadence: "daily", preferred_hour: 9)
    success = AutoSync::ScheduleUpserter::Result.new(success?: true, schedule: schedule)
    allow(AutoSync::ScheduleUpserter).to receive(:call).and_return(success)

    patch admin_bank_connection_sync_schedule_path(connection), params: {
      sync_schedule: { enabled: "1", cadence: "daily", preferred_hour: "9" }
    }

    expect(AutoSync::ScheduleUpserter).to have_received(:call) do |kwargs|
      expect(kwargs[:connection]).to eq(connection)
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:input]).to be_a(AutoSync::ScheduleUpserter::Input)
      expect(kwargs[:input].cadence).to eq("daily")
      expect(kwargs[:input].preferred_hour).to eq("9")
    end
    expect(response).to redirect_to(admin_transaction_syncs_path)
  end

  it "PATCH /admin/bank_connections/:bc_id/sync_schedule re-renders :edit with 422 on failure" do
    user = create(:user)
    connection = create(:bank_connection, tpp_credential: create(:tpp_credential, user: user))
    sign_in user
    invalid = SyncSchedule.new(bank_connection: connection)
    failure = AutoSync::ScheduleUpserter::Result.new(success?: false, schedule: invalid, error_messages: [ "bad" ])
    allow(AutoSync::ScheduleUpserter).to receive(:call).and_return(failure)

    patch admin_bank_connection_sync_schedule_path(connection), params: {
      sync_schedule: { enabled: "1", cadence: "daily", preferred_hour: "9" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(flash.now[:alert] || flash[:alert]).to match(/bad/)
  end

  it "GET /admin/bank_connections without a sign-in redirects to /admin/sign_in" do
    create(:user)
    get admin_bank_connections_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
