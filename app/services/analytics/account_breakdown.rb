# frozen_string_literal: true

module Analytics
  # Spend distribution across BankAccounts in a scope. Powers the donut
  # chart on the dashboard. Click handler narrows the dashboard filter
  # to a single account — same URL param contract as the chips.
  class AccountBreakdown
    Row = Struct.new(:account, :amount_cents, :count, :currency, keyword_init: true) do
      def amount = Money.new(amount_cents, currency)
    end

    def self.call(scope, user:, currency:)
      pluck = scope.spend
                   .group(:bank_account_id)
                   .order(Arel.sql("SUM(amount_cents) DESC"))
                   .pluck(Arel.sql("bank_account_id, SUM(amount_cents), COUNT(*)"))

      # Hydrate through the user's own accounts (synced + cash wallets).
      # Any id outside that set drops out — defense-in-depth on top of
      # `Analytics::Filter`'s account_ids gate.
      owned_ids = user.all_bank_account_ids
      accounts = BankAccount.where(id: pluck.map(&:first) & owned_ids).index_by(&:id)

      pluck.filter_map do |account_id, sum, count|
        account = accounts[account_id]
        next nil unless account
        Row.new(account: account, amount_cents: sum.to_i, count: count.to_i, currency: currency)
      end
    end
  end
end
