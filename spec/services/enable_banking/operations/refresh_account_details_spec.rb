# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableBanking::Operations::RefreshAccountDetails do
  it "overwrites the 11 EB-mirrored fields, stamps details_fetched_at, and persists raw_details" do
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, currency: "PLN", iban: "PL98291000060000000002844207", holder_name: "Maciej Biel", product: "Personal Account")
    account = create(:bank_account, tpp_credential: tpp, uid: uid, currency: "PLN", iban: "STALE", name: "STALE", details_fetched_at: nil)

    described_class.call(account)

    account.reload
    expect(account.iban).to eq("PL98291000060000000002844207")
    expect(account.name).to eq("Maciej Biel")
    expect(account.product).to eq("Personal Account")
    expect(account.currency).to eq("PLN")
    expect(account.account_servicer).to eq({ "bic_fi" => "FAKEPLPW" })
    expect(account.raw_details).to be_a(Hash)
    expect(account.details_fetched_at).to be_present
  end

  it "preserves existing field values when EB returns the field as null (per-bank fill rates differ)" do
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    session_id = fake_eb.add_session(aspsp_name: "PKO BP", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, holder_name: "", iban: "PL76102044050000240206731378", product: nil)
    account = create(:bank_account, tpp_credential: tpp, uid: uid, name: "Existing Name", product: "Existing Product")

    described_class.call(account)

    account.reload
    expect(account.name).to eq("Existing Name")
    expect(account.product).to eq("Existing Product")
  end

  it "re-syncs the OwnAccountMerchantSyncer rules over all account IBANs (Revolut LT IBAN exposure case)" do
    user = create(:user)
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    session_id = fake_eb.add_session(aspsp_name: "Revolut", country: "PL")
    uid = fake_eb.add_account(session_id: session_id, iban: "PL98291000060000000002844207", alternate_ibans: [ "LT133250071731583449" ])
    account = create(:bank_account, tpp_credential: tpp, uid: uid, iban: "PL98291000060000000002844207", all_account_ids: [])

    described_class.call(account)

    merchant = user.merchants.find_by(slug: "own_account_#{uid[0, 8]}")
    expect(merchant).to be_present
    rules = merchant.merchant_rules.where(field: "counterparty_iban").pluck(:pattern)
    expect(rules).to include("PL98291000060000000002844207", "LT133250071731583449")
  end

  it "raises Failed and does not touch the account when /accounts/:uid/details returns a failure" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    session_id = fake_eb.add_session(aspsp_name: "Fake Bank", country: "PL")
    uid = fake_eb.add_account(session_id: session_id)
    account = create(:bank_account, tpp_credential: tpp, uid: uid, name: "Untouched", details_fetched_at: nil)
    fake_eb.simulate_failure(method: :get, path: "/accounts/#{uid}/details", status: 500, error: "Internal Server Error")

    expect {
      described_class.call(account)
    }.to raise_error(described_class::Failed, /Internal Server Error/)

    expect(account.reload.name).to eq("Untouched")
    expect(account.details_fetched_at).to be_nil
  end
end
