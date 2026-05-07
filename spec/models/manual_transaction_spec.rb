# frozen_string_literal: true

# == Schema Information
#
# Table name: manual_transactions
#
#  id                         :bigint           not null, primary key
#  amount_cents               :bigint           not null
#  booking_date               :date             not null
#  counterparty_kind          :string           default("unknown"), not null
#  counterparty_name          :string
#  currency                   :string(3)        not null
#  direction                  :string           not null
#  note                       :text
#  payment_method             :string
#  source                     :string           default("manual"), not null
#  status                     :string           default("booked"), not null
#  title                      :text
#  transaction_date           :date
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  bank_account_id            :bigint           not null
#  created_by_user_id         :bigint           not null
#  linked_bank_transaction_id :bigint
#
# Indexes
#
#  idx_manual_transactions_one_per_linked_bank_tx                 (linked_bank_transaction_id) UNIQUE WHERE (linked_bank_transaction_id IS NOT NULL)
#  index_manual_transactions_on_bank_account_id                   (bank_account_id)
#  index_manual_transactions_on_bank_account_id_and_booking_date  (bank_account_id,booking_date)
#  index_manual_transactions_on_counterparty_kind                 (counterparty_kind)
#  index_manual_transactions_on_created_by_user_id                (created_by_user_id)
#  index_manual_transactions_on_linked_bank_transaction_id        (linked_bank_transaction_id)
#  index_manual_transactions_on_payment_method                    (payment_method)
#  index_manual_transactions_on_status                            (status)
#
# Foreign Keys
#
#  fk_rails_...  (bank_account_id => bank_accounts.id)
#  fk_rails_...  (created_by_user_id => users.id)
#  fk_rails_...  (linked_bank_transaction_id => bank_transactions.id)
#
require "rails_helper"

RSpec.describe ManualTransaction do
  it "rejects amount_cents of zero or negative and accepts positive values" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")

    zero = build(:manual_transaction, bank_account: wallet, created_by_user: user, amount_cents: 0)
    negative = build(:manual_transaction, bank_account: wallet, created_by_user: user, amount_cents: -1)
    positive = build(:manual_transaction, bank_account: wallet, created_by_user: user, amount_cents: 1)

    expect(zero).not_to be_valid
    expect(zero.errors[:amount_cents]).to include("must be greater than 0")
    expect(negative).not_to be_valid
    expect(negative.errors[:amount_cents]).to include("must be greater than 0")
    expect(positive).to be_valid
  end

  it "rejects manual transactions on a non-manual bank account with the wallet error" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    synced_account = create(:bank_account, tpp_credential: tpp, currency: "PLN")

    record = build(:manual_transaction, bank_account: synced_account, created_by_user: user, currency: "PLN")

    expect(record).not_to be_valid
    expect(record.errors[:bank_account]).to include("must be a manual cash wallet")
  end

  it "enforces currency_matches_wallet across mismatched, matched, and blank cases" do
    user = create(:user)
    pln_wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")

    mismatched = build(:manual_transaction, bank_account: pln_wallet, created_by_user: user, currency: "EUR")
    matched    = build(:manual_transaction, bank_account: pln_wallet, created_by_user: user, currency: "PLN")
    blank      = build(:manual_transaction, bank_account: pln_wallet, created_by_user: user, currency: "")

    expect(mismatched).not_to be_valid
    expect(mismatched.errors[:currency]).to include("must match wallet currency (PLN)")

    expect(matched).to be_valid

    expect(blank).not_to be_valid
    expect(blank.errors[:currency]).to include("can't be blank")
    expect(blank.errors[:currency]).not_to include("must match wallet currency (PLN)")
  end

  it "returns a positive Money for credits and the negation for debits in signed_amount" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    credit = create(:manual_transaction, bank_account: wallet, created_by_user: user, amount_cents: 50_00, currency: "PLN", direction: "credit")
    debit  = create(:manual_transaction, bank_account: wallet, created_by_user: user, amount_cents: 50_00, currency: "PLN", direction: "debit")

    expect(credit.signed_amount).to eq(Money.new(5000, "PLN"))
    expect(debit.signed_amount).to eq(Money.new(-5000, "PLN"))
  end

  it "returns bank_account.manual_owner for #user even when created_by_user differs" do
    owner = create(:user)
    creator = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: owner, currency: "PLN")
    record = create(:manual_transaction, bank_account: wallet, created_by_user: creator, currency: "PLN")

    expect(record.user).to eq(owner)
    expect(record.user).not_to eq(creator)
  end

  it "scopes for_user(user) by manual_owner_id and excludes other owners' wallets" do
    owner_a = create(:user)
    owner_b = create(:user)
    wallet_a = create(:bank_account, :cash, manual_owner: owner_a, currency: "PLN")
    wallet_b = create(:bank_account, :cash, manual_owner: owner_b, currency: "PLN")
    tx_a = create(:manual_transaction, bank_account: wallet_a, created_by_user: owner_a, currency: "PLN")
    tx_b = create(:manual_transaction, bank_account: wallet_b, created_by_user: owner_b, currency: "PLN")

    expect(described_class.for_user(owner_a).pluck(:id)).to contain_exactly(tx_a.id)
    expect(described_class.for_user(owner_b).pluck(:id)).to contain_exactly(tx_b.id)
  end

  it "raises RecordNotUnique on a second manual transaction linked to the same bank transaction" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    synced = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    bank_tx = create(:bank_transaction, :atm_withdrawal, bank_account: synced, currency: "PLN")
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN", linked_bank_transaction: bank_tx, source: "atm_link")

    expect {
      create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN", linked_bank_transaction: bank_tx, source: "atm_link")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "delegates merchant_id and category_id to enrichment, returning nil when enrichment is absent" do
    user = create(:user)
    wallet = create(:bank_account, :cash, manual_owner: user, currency: "PLN")
    record = create(:manual_transaction, bank_account: wallet, created_by_user: user, currency: "PLN")

    expect(record.enrichment).to be_nil
    expect(record.merchant_id).to be_nil
    expect(record.category_id).to be_nil

    merchant = create(:merchant, user: user)
    category = create(:category, user: user, name: "Cash", slug: "cash_category", path: "cash_category")
    create(:transaction_enrichment, enrichable: record, source: "manual", merchant: merchant, category: category, category_overridden: true)

    expect(record.reload.merchant_id).to eq(merchant.id)
    expect(record.category_id).to eq(category.id)
  end
end
