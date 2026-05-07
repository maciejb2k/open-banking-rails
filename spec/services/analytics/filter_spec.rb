# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::Filter do
  def setup_user_with_accounts(currencies: [ "PLN" ])
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    accounts = currencies.each_with_index.map do |c, i|
      create(:bank_account, tpp_credential: tpp, currency: c, name: "Acct #{i}")
    end
    [ user, accounts ]
  end

  it "defaults to month-to-date period when no from/to params are supplied" do
    user, _ = setup_user_with_accounts

    travel_to(Date.new(2026, 5, 7)) do
      filter = described_class.new(user: user, params: {})

      expect(filter.period.from).to eq(Date.new(2026, 5, 1))
      expect(filter.period.to).to eq(Date.new(2026, 5, 7))
    end
  end

  it "defaults account_ids to the user's full owned-account list and rejects forged ids" do
    user_a, accounts_a = setup_user_with_accounts
    user_b, accounts_b = setup_user_with_accounts

    default_filter = described_class.new(user: user_a, params: {})
    expect(default_filter.account_ids).to match_array(accounts_a.map(&:id))

    forged_filter = described_class.new(user: user_a, params: { account_ids: [ accounts_a.first.id, accounts_b.first.id ] })
    expect(forged_filter.account_ids).to eq([ accounts_a.first.id ])
  end

  it "treats accounts=none as the explicit zero state, distinct from all_accounts?" do
    user, accounts = setup_user_with_accounts

    none_filter = described_class.new(user: user, params: { accounts: "none" })
    all_filter  = described_class.new(user: user, params: {})

    expect(none_filter.none?).to be(true)
    expect(none_filter.account_ids).to eq([])
    expect(none_filter.all_accounts?).to be(false)

    expect(all_filter.none?).to be(false)
    expect(all_filter.all_accounts?).to be(true)
    expect(all_filter.account_ids).to match_array(accounts.map(&:id))
  end

  it "picks dominant currency by ledger count and respects an explicit known currency override" do
    user, accounts = setup_user_with_accounts(currencies: [ "PLN", "EUR" ])
    pln_account, eur_account = accounts
    create(:bank_transaction, bank_account: pln_account, currency: "PLN")
    create(:bank_transaction, bank_account: pln_account, currency: "PLN")
    create(:bank_transaction, bank_account: eur_account, currency: "EUR")

    default_filter = described_class.new(user: user, params: {})
    expect(default_filter.currency).to eq("PLN")

    explicit_filter = described_class.new(user: user, params: { currency: "EUR" })
    expect(explicit_filter.currency).to eq("EUR")

    bogus_filter = described_class.new(user: user, params: { currency: "USD" })
    expect(bogus_filter.currency).to eq("PLN")
  end

  it "picks the smart bucket default by length: ≤31d → :day, ≤180d → :week, else → :month" do
    user, _ = setup_user_with_accounts

    short  = described_class.new(user: user, params: { from: "2026-05-01", to: "2026-05-15" })
    medium = described_class.new(user: user, params: { from: "2026-01-01", to: "2026-05-01" })
    long   = described_class.new(user: user, params: { from: "2025-01-01", to: "2026-05-01" })

    expect(short.bucket).to eq(:day)
    expect(medium.bucket).to eq(:week)
    expect(long.bucket).to eq(:month)
  end

  it "to_query_params omits accounts and bucket when they're at default state" do
    user, accounts = setup_user_with_accounts

    travel_to(Date.new(2026, 5, 7)) do
      default_filter = described_class.new(user: user, params: {})
      expect(default_filter.to_query_params.keys).not_to include(:accounts, :account_ids, :bucket)

      explicit_filter = described_class.new(user: user, params: { account_ids: [ accounts.first.id ], bucket: "week" })
      expect(explicit_filter.to_query_params).to include(account_ids: [ accounts.first.id ], bucket: :week)
    end
  end
end
