# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auto-sync cron tick journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
    Sidekiq::Testing.fake!
  end

  it "dispatches a scheduled transaction_sync, runs it inline to terminal succeeded, advances next_run_at, and observes the breaker as a clean reset" do
    user = create_seeded_user(email: "tick-happy@example.test")
    connection, account_uid = attach_authorized_connection(user, slug: "pko_bp", aspsp_name: "PKO BP", country: "PL", iban_suffix: "001")
    fake_eb.add_transaction(
      account_uid:        account_uid,
      amount_cents:       -19_99,
      direction:          "debit",
      booking_date:       Date.current,
      title:              "BIEDRONKA WARSZAWA",
      payment_method_hint: "card"
    )
    schedule = make_schedule_due(connection)
    sign_in_as(user)

    Sidekiq::Testing.inline! do
      AutoSync::DispatcherJob.perform_now
    end

    runs = OperationRun.where(triggered_by_user: user, kind: "transaction_sync", trigger: "scheduled")
    expect(runs.count).to eq(1)
    run = runs.first
    expect(run.status).to eq("succeeded")
    expect(run.subject).to eq(connection)
    expect(BankTransaction.for_user(user).count).to eq(1)
    expect(BankTransaction.for_user(user).first.title).to include("BIEDRONKA")

    schedule.reload
    expect(schedule.next_run_at).to be > Time.current + 12.hours
    expect(schedule.last_dispatched_at).to be_within(2.minutes).of(Time.current)
    expect(schedule.consecutive_failures).to eq(0)
    expect(schedule.paused_until).to be_nil

    assert_no_running_operation_runs!
    assert_ledger_sums_match!(user)
  end

  it "is a no-op when the only schedule's next_run_at is in the future, leaving the cursor untouched" do
    user = create_seeded_user(email: "tick-not-due@example.test")
    connection, _ = attach_authorized_connection(user, slug: "pko_bp", aspsp_name: "PKO BP", country: "PL", iban_suffix: "002")
    schedule = SyncSchedule.create!(
      bank_connection: connection,
      enabled:         true,
      cadence:         "daily",
      preferred_hour:  8,
      next_run_at:     1.day.from_now
    )
    original_next_run = schedule.next_run_at
    sign_in_as(user)

    expect {
      Sidekiq::Testing.inline! do
        AutoSync::DispatcherJob.perform_now
      end
    }.not_to change(OperationRun, :count)

    schedule.reload
    expect(schedule.next_run_at).to be_within(1.second).of(original_next_run)
    expect(schedule.last_dispatched_at).to be_nil
  end

  it "creates one independent run per due connection in a single tick" do
    user = create_seeded_user(email: "tick-fanout@example.test")
    conn_a, uid_a = attach_authorized_connection(user, slug: "pko_bp", aspsp_name: "PKO BP", country: "PL", iban_suffix: "010")
    conn_b, uid_b = attach_authorized_connection(user, slug: "revolut_lt", aspsp_name: "Revolut LT", country: "LT", iban_suffix: "011", currency: "EUR")
    fake_eb.add_transaction(account_uid: uid_a, amount_cents: -10_00, direction: "debit", booking_date: Date.current, title: "ZABKA")
    fake_eb.add_transaction(account_uid: uid_b, amount_cents: -25_00, currency: "EUR", direction: "debit", booking_date: Date.current, title: "Spotify AB")
    make_schedule_due(conn_a)
    make_schedule_due(conn_b)
    sign_in_as(user)

    expect {
      Sidekiq::Testing.inline! do
        AutoSync::DispatcherJob.perform_now
      end
    }.to change { OperationRun.where(kind: "transaction_sync", trigger: "scheduled").count }.by(2)

    statuses = OperationRun.where(triggered_by_user: user, trigger: "scheduled")
                            .order(:id)
                            .pluck(:subject_id, :status)
    expect(statuses).to contain_exactly([ conn_a.id, "succeeded" ], [ conn_b.id, "succeeded" ])
    expect(BankTransaction.for_user(user).count).to eq(2)
    assert_no_running_operation_runs!
  end

  def create_seeded_user(email:)
    user = User.create!(email: email, password: "Password123!", name: "Tick User")
    Seeders::Categories.call(user)
    Seeders::MerchantRules.call(user)
    user
  end

  def attach_authorized_connection(user, slug:, aspsp_name:, country:, iban_suffix:, currency: "PLN")
    credential = user.tpp_credentials.find_or_create_by!(name: "#{aspsp_name} (Tick)") do |c|
      c.provider        = "enable_banking"
      c.environment     = "SANDBOX"
      c.status          = "active"
      c.primary         = user.tpp_credentials.none?
      c.application_id  = "fake-app-#{slug}"
      c.redirect_url    = "http://localhost:3000/admin/oauth/enable_banking/callback"
      c.private_key_pem = "fake-pem"
    end
    connection = credential.bank_connections.create!(
      bank_slug:           slug,
      bank_country:        country,
      bank_name:           aspsp_name,
      status:              "authorized",
      psu_type:            "personal",
      session_id:          "sess-#{SecureRandom.hex(4)}",
      valid_until:         30.days.from_now,
      authorized_at:       Time.current,
      access_balances:     true,
      access_transactions: true
    )
    session_id = fake_eb.add_session(aspsp_name: aspsp_name, country: country, valid_until: 30.days.from_now)
    iban = "PL61109010140000071219#{iban_suffix.rjust(6, '0')}"
    uid = fake_eb.add_account(
      session_id:    session_id,
      uid:           "acc-#{slug}-#{SecureRandom.hex(3)}",
      currency:      currency,
      balance_cents: 100_00,
      holder_name:   user.name,
      iban:          iban
    )
    BankAccount.create!(
      uid:                     uid,
      iban:                    iban,
      currency:                currency,
      name:                    "#{aspsp_name} Personal",
      product:                 "Personal",
      cash_account_type:       "CACC",
      status:                  "active",
      tpp_credential:          credential,
      current_bank_connection: connection,
      all_account_ids:         []
    )
    [ connection, uid ]
  end

  def make_schedule_due(connection)
    SyncSchedule.create!(
      bank_connection: connection,
      enabled:         true,
      cadence:         "daily",
      preferred_hour:  8,
      next_run_at:     1.minute.ago
    )
  end
end
