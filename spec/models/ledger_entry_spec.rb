# frozen_string_literal: true

require "rails_helper"

RSpec.describe LedgerEntry do
  it "exists in the test schema as a database view" do
    expect(ActiveRecord::Base.connection.view_exists?(:ledger_entries)).to be(true)
  end

  it "satisfies the sum-integrity invariant for a single user with mixed bank + manual rows" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    synced = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    cash = create(:bank_account, :cash, manual_owner: user, currency: "PLN")

    create(:bank_transaction, bank_account: synced, amount_cents: 200_00, direction: "debit",  currency: "PLN")
    create(:bank_transaction, bank_account: synced, amount_cents: 300_00, direction: "debit",  currency: "PLN")
    create(:bank_transaction, bank_account: synced, amount_cents: 1_000_00, direction: "credit", currency: "PLN")
    create(:bank_transaction, bank_account: synced, amount_cents: 50_00,  direction: "debit",  currency: "PLN")
    create(:bank_transaction, bank_account: synced, amount_cents: 75_00,  direction: "credit", currency: "PLN")

    create(:manual_transaction, user: user, bank_account: cash, amount_cents: 25_00, direction: "debit",  currency: "PLN")
    create(:manual_transaction, user: user, bank_account: cash, amount_cents: 80_00, direction: "credit", currency: "PLN")
    create(:manual_transaction, user: user, bank_account: cash, amount_cents: 10_00, direction: "debit",  currency: "PLN")

    bank_signed   = BankTransaction.for_user(user).sum("CASE direction WHEN 'credit' THEN amount_cents ELSE -amount_cents END")
    manual_signed = ManualTransaction.for_user(user).sum("CASE direction WHEN 'credit' THEN amount_cents ELSE -amount_cents END")

    expect(LedgerEntry.for_user(user).sum(:signed_amount_cents)).to eq(bank_signed + manual_signed)
  end

  it "exposes exactly one ledger row per source-table row (no leaks, no duplicates)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    cash = create(:bank_account, :cash, manual_owner: user)

    3.times { create(:bank_transaction, bank_account: account) }
    2.times { create(:manual_transaction, user: user, bank_account: cash) }

    bank_count   = BankTransaction.for_user(user).count
    manual_count = ManualTransaction.for_user(user).count

    expect(LedgerEntry.for_user(user).count).to eq(bank_count + manual_count)
    expect(LedgerEntry.for_user(user).where(source_type: "BankTransaction").count).to eq(bank_count)
    expect(LedgerEntry.for_user(user).where(source_type: "ManualTransaction").count).to eq(manual_count)
  end

  it "computes signed_amount_cents as positive for credits and negative for debits regardless of source" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    cash = create(:bank_account, :cash, manual_owner: user)

    bank_credit = create(:bank_transaction, bank_account: account, amount_cents: 100_00, direction: "credit")
    bank_debit  = create(:bank_transaction, bank_account: account, amount_cents: 200_00, direction: "debit")
    cash_credit = create(:manual_transaction, user: user, bank_account: cash, amount_cents: 30_00, direction: "credit")
    cash_debit  = create(:manual_transaction, user: user, bank_account: cash, amount_cents: 50_00, direction: "debit")

    rows = LedgerEntry.for_user(user)
    expect(rows.find_by(source_type: "BankTransaction",   source_id: bank_credit.id).signed_amount_cents).to eq(100_00)
    expect(rows.find_by(source_type: "BankTransaction",   source_id: bank_debit.id).signed_amount_cents).to eq(-200_00)
    expect(rows.find_by(source_type: "ManualTransaction", source_id: cash_credit.id).signed_amount_cents).to eq(30_00)
    expect(rows.find_by(source_type: "ManualTransaction", source_id: cash_debit.id).signed_amount_cents).to eq(-50_00)
  end

  it "resolves effective_category to the override when both override and merchant default are present" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    override = create(:category, user: user, slug: "override_cat", path: "override_cat")
    default  = create(:category, user: user, slug: "default_cat",  path: "default_cat")
    merchant = create(:merchant, user: user, default_category: default)
    tx = create(:bank_transaction, bank_account: account)
    create(:transaction_enrichment, enrichable: tx, merchant: merchant, category: override, source: "manual", category_overridden: true)

    row = LedgerEntry.find_by(source_type: "BankTransaction", source_id: tx.id)
    expect(row.effective_category_id).to eq(override.id)
    expect(row.category_path.to_s).to eq("override_cat")
  end

  it "falls back to the merchant default category when no override is set" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    default  = create(:category, user: user, slug: "default_cat", path: "default_cat")
    merchant = create(:merchant, user: user, default_category: default)
    tx = create(:bank_transaction, bank_account: account)
    create(:transaction_enrichment, enrichable: tx, merchant: merchant, category: nil, source: "system_rule")

    row = LedgerEntry.find_by(source_type: "BankTransaction", source_id: tx.id)
    expect(row.effective_category_id).to eq(default.id)
    expect(row.category_path.to_s).to eq("default_cat")
  end

  it "yields NULL effective_category_id when neither override nor merchant default exists" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    tx = create(:bank_transaction, bank_account: account)

    row = LedgerEntry.find_by(source_type: "BankTransaction", source_id: tx.id)
    expect(row.effective_category_id).to be_nil
    expect(row.category_path).to be_nil
  end

  it "narrows spend to debits on expense-kind categories and excludes refunds, transfers, and unmatched rows" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    expense_cat  = create(:category, user: user, kind: "expense",  slug: "exp", path: "exp")
    transfer_cat = create(:category, user: user, kind: "transfer", slug: "tr",  path: "tr")
    expense_merchant  = create(:merchant, user: user, default_category: expense_cat)
    transfer_merchant = create(:merchant, user: user, default_category: transfer_cat)

    spend_tx = create(:bank_transaction, bank_account: account, direction: "debit", amount_cents: 100_00)
    create(:transaction_enrichment, enrichable: spend_tx, merchant: expense_merchant, source: "system_rule")

    refund_tx = create(:bank_transaction, bank_account: account, direction: "credit", amount_cents: 25_00)
    create(:transaction_enrichment, enrichable: refund_tx, merchant: expense_merchant, source: "system_rule")

    transfer_tx = create(:bank_transaction, bank_account: account, direction: "debit", amount_cents: 50_00)
    create(:transaction_enrichment, enrichable: transfer_tx, merchant: transfer_merchant, source: "system_rule")

    create(:bank_transaction, bank_account: account, direction: "debit", amount_cents: 9_99)

    spend_rows = LedgerEntry.for_user(user).spend
    expect(spend_rows.count).to eq(1)
    expect(spend_rows.sum(:signed_amount_cents)).to eq(-100_00)
  end

  it "narrows income to credits on income-kind categories" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    income_cat = create(:category, user: user, kind: "income", slug: "inc", path: "inc")
    income_merchant = create(:merchant, user: user, default_category: income_cat)

    salary = create(:bank_transaction, bank_account: account, direction: "credit", amount_cents: 5_000_00)
    create(:transaction_enrichment, enrichable: salary, merchant: income_merchant, source: "system_rule")

    bogus_debit = create(:bank_transaction, bank_account: account, direction: "debit", amount_cents: 100_00)
    create(:transaction_enrichment, enrichable: bogus_debit, merchant: income_merchant, source: "system_rule")

    income_rows = LedgerEntry.for_user(user).income
    expect(income_rows.count).to eq(1)
    expect(income_rows.sum(:signed_amount_cents)).to eq(5_000_00)
  end

  it "isolates rows across users in for_user" do
    user_a = create(:user)
    user_b = create(:user)
    tpp_a = create(:tpp_credential, user: user_a)
    tpp_b = create(:tpp_credential, user: user_b)
    account_a = create(:bank_account, tpp_credential: tpp_a)
    account_b = create(:bank_account, tpp_credential: tpp_b)
    cash_b    = create(:bank_account, :cash, manual_owner: user_b)

    create(:bank_transaction, bank_account: account_a)
    create(:bank_transaction, bank_account: account_b)
    create(:manual_transaction, user: user_b, bank_account: cash_b)

    expect(LedgerEntry.for_user(user_a).count).to eq(1)
    expect(LedgerEntry.for_user(user_b).count).to eq(2)

    a_account_ids = LedgerEntry.for_user(user_a).pluck(:bank_account_id).uniq
    b_account_ids = LedgerEntry.for_user(user_b).pluck(:bank_account_id).uniq
    expect(a_account_ids & b_account_ids).to be_empty
  end

  it "raises ActiveRecord::ReadOnlyRecord on update, save, and destroy attempts" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    create(:bank_transaction, bank_account: account)

    row = LedgerEntry.first
    expect(row.readonly?).to be(true)
    expect { row.update(amount_cents: 1) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { row.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { row.delete }.to raise_error(ActiveRecord::ActiveRecordError)
  end

  it "mirrors category_path to the resolved category's ltree path" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    cat = create(:category, user: user, slug: "food", path: "food", kind: "expense")
    merchant = create(:merchant, user: user, default_category: cat)
    tx = create(:bank_transaction, bank_account: account)
    create(:transaction_enrichment, enrichable: tx, merchant: merchant, source: "system_rule")

    row = LedgerEntry.find_by(source_type: "BankTransaction", source_id: tx.id)
    expect(row.category_path.to_s).to eq("food")
  end

  it "filters under_path to subtree containment, returning none for an empty input" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    food = create(:category, user: user, slug: "food", path: "food", kind: "expense")
    supermarket = create(:category, user: user, slug: "food_supermarket", path: "food.supermarket", kind: "expense")
    transport = create(:category, user: user, slug: "transport", path: "transport", kind: "expense")
    food_merchant = create(:merchant, user: user, default_category: supermarket)
    transport_merchant = create(:merchant, user: user, default_category: transport)

    in_food = create(:bank_transaction, bank_account: account, direction: "debit", amount_cents: 100_00)
    create(:transaction_enrichment, enrichable: in_food, merchant: food_merchant, source: "system_rule")

    out_of_food = create(:bank_transaction, bank_account: account, direction: "debit", amount_cents: 50_00)
    create(:transaction_enrichment, enrichable: out_of_food, merchant: transport_merchant, source: "system_rule")

    expect(LedgerEntry.under_path("food").pluck(:source_id)).to contain_exactly(in_food.id)
    expect(LedgerEntry.under_path([])).to eq(LedgerEntry.none)
    expect(LedgerEntry.under_path([ food, "transport" ]).pluck(:source_id)).to contain_exactly(in_food.id, out_of_food.id)
  end

  it "round-trips source_record back to the AR instance with matching signed amount" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    bank_tx = create(:bank_transaction, bank_account: account, direction: "debit", amount_cents: 100_00)
    cash = create(:bank_account, :cash, manual_owner: user)
    cash_tx = create(:manual_transaction, user: user, bank_account: cash, direction: "credit", amount_cents: 30_00)

    bank_row = LedgerEntry.find_by(source_type: "BankTransaction", source_id: bank_tx.id)
    cash_row = LedgerEntry.find_by(source_type: "ManualTransaction", source_id: cash_tx.id)

    expect(bank_row.source_record).to eq(bank_tx)
    expect(cash_row.source_record).to eq(cash_tx)
    expect(bank_row.signed_amount_cents).to eq(bank_tx.signed_amount.cents)
    expect(cash_row.signed_amount_cents).to eq(cash_tx.signed_amount.cents)
  end

  it "filters counterparty_kind via to_self and with_external_counterparty" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)

    create(:bank_transaction, bank_account: account, counterparty_kind: "self")
    create(:bank_transaction, bank_account: account, counterparty_kind: "external")
    create(:bank_transaction, bank_account: account, counterparty_kind: "unknown")

    expect(LedgerEntry.for_user(user).to_self.count).to eq(1)
    expect(LedgerEntry.for_user(user).with_external_counterparty.count).to eq(2)
  end

  it "keeps pending rows visible in all but excludes them from booked" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    create(:bank_transaction, bank_account: account, status: "booked")
    create(:bank_transaction, bank_account: account, status: "pending")

    expect(LedgerEntry.for_user(user).count).to eq(2)
    expect(LedgerEntry.for_user(user).booked.count).to eq(1)
    expect(LedgerEntry.for_user(user).pending.count).to eq(1)
  end

  it "re-categorizes rows on the fly when a Category's kind changes (no re-enrichment)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    account = create(:bank_account, tpp_credential: tpp)
    cat = create(:category, user: user, slug: "morphing", path: "morphing", kind: "expense")
    merchant = create(:merchant, user: user, default_category: cat)
    tx = create(:bank_transaction, bank_account: account, direction: "debit", amount_cents: 75_00)
    create(:transaction_enrichment, enrichable: tx, merchant: merchant, source: "system_rule")

    expect(LedgerEntry.for_user(user).spend.count).to eq(1)

    cat.update!(kind: "transfer")

    expect(LedgerEntry.for_user(user).spend.count).to eq(0)
    expect(LedgerEntry.for_user(user).transfers.count).to eq(1)
  end

  it "sums signed_amount_cents across mixed currencies as a literal cents addition without conversion" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    pln_account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    eur_account = create(:bank_account, tpp_credential: tpp, currency: "EUR")
    create(:bank_transaction, bank_account: pln_account, currency: "PLN", direction: "debit",  amount_cents: 100_00)
    create(:bank_transaction, bank_account: eur_account, currency: "EUR", direction: "credit", amount_cents: 5_00)

    expect(LedgerEntry.for_user(user).sum(:signed_amount_cents)).to eq(-100_00 + 5_00)
  end

  it "groups multi-currency sums per currency to allow per-currency aggregations" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    pln_account = create(:bank_account, tpp_credential: tpp, currency: "PLN")
    eur_account = create(:bank_account, tpp_credential: tpp, currency: "EUR")
    create(:bank_transaction, bank_account: pln_account, currency: "PLN", direction: "debit",  amount_cents: 100_00)
    create(:bank_transaction, bank_account: pln_account, currency: "PLN", direction: "debit",  amount_cents: 50_00)
    create(:bank_transaction, bank_account: eur_account, currency: "EUR", direction: "credit", amount_cents: 5_00)

    by_currency = LedgerEntry.for_user(user).group(:currency).sum(:signed_amount_cents)
    expect(by_currency["PLN"]).to eq(-150_00)
    expect(by_currency["EUR"]).to eq(5_00)
  end
end
