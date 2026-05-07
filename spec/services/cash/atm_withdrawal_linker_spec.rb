# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::AtmWithdrawalLinker do
  def seed_atm_withdrawal(user:, amount_cents: 200_00, payment_method: "blik_atm", direction: "debit")
    Seeders::Categories.call(user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp, bank_name: "Bank XYZ")
    account = create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, currency: "PLN")
    create(:bank_transaction, bank_account: account, amount_cents: amount_cents, currency: "PLN", payment_method: payment_method, direction: direction)
  end

  it "creates a linked credit ManualTransaction with source atm_link, payment_method cash_atm_topup, and matching cents/currency" do
    user = create(:user, :cash_on)
    bank_tx = seed_atm_withdrawal(user: user, amount_cents: 200_00)

    topup = described_class.link!(bank_tx)

    expect(topup).to be_persisted
    expect(topup.source).to eq("atm_link")
    expect(topup.payment_method).to eq("cash_atm_topup")
    expect(topup.direction).to eq("credit")
    expect(topup.amount_cents).to eq(200_00)
    expect(topup.linked_bank_transaction_id).to eq(bank_tx.id)
    expect(topup.bank_account.manual?).to be(true)
    expect(topup.bank_account.manual_owner).to eq(user)
    expect(topup.title).to include("ATM withdrawal")
    expect(topup.enrichment.source).to eq("system_fallback")
    expect(topup.enrichment.category).to eq(user.categories.find_by(slug: "cash_atm_topup"))
  end

  it "is idempotent — re-linking the same bank_transaction returns nil (already_linked guard)" do
    user = create(:user, :cash_on)
    bank_tx = seed_atm_withdrawal(user: user)
    described_class.link!(bank_tx)

    expect {
      result = described_class.link!(bank_tx)
      expect(result).to be_nil
    }.not_to change(ManualTransaction, :count)
  end

  it "returns nil for ineligible payment_method (e.g. card) without writing anything" do
    user = create(:user, :cash_on)
    bank_tx = seed_atm_withdrawal(user: user, payment_method: "card")

    expect {
      result = described_class.link!(bank_tx)
      expect(result).to be_nil
    }.not_to change(ManualTransaction, :count)
  end

  it "returns nil for credit-direction BLIK ATM (refund) since only debits are linkable" do
    user = create(:user, :cash_on)
    bank_tx = seed_atm_withdrawal(user: user, direction: "credit")

    expect(described_class.link!(bank_tx)).to be_nil
    expect(ManualTransaction.where(linked_bank_transaction_id: bank_tx.id).count).to eq(0)
  end

  it "returns nil and writes nothing when the user has track_cash? false" do
    user = create(:user, track_cash: false)
    bank_tx = seed_atm_withdrawal(user: user)

    expect {
      result = described_class.link!(bank_tx)
      expect(result).to be_nil
    }.not_to change(ManualTransaction, :count)
  end

  it "swallows ActiveRecord::RecordNotUnique on race and returns nil (DB partial UNIQUE safety net)" do
    user = create(:user, :cash_on)
    bank_tx = seed_atm_withdrawal(user: user)

    other_owner = create(:user)
    foreign_wallet = create(:bank_account, :cash, manual_owner: other_owner, currency: "PLN")
    create(:manual_transaction, bank_account: foreign_wallet, created_by_user: other_owner, currency: "PLN", linked_bank_transaction_id: bank_tx.id, source: "atm_link")

    user_wallet_ids = BankAccount.where(manual_owner_id: user.id).pluck(:id)
    user_manuals_before = ManualTransaction.where(bank_account_id: user_wallet_ids).count

    result = described_class.link!(bank_tx)
    expect(result).to be_nil
    expect(ManualTransaction.where(bank_account_id: user_wallet_ids).count).to eq(user_manuals_before)
  end
end
