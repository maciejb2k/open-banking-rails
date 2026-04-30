# frozen_string_literal: true

module Analytics
  # Spend distribution across BankAccounts in a scope. Powers the donut
  # chart on the dashboard. Click handler narrows the dashboard filter
  # to a single account — same URL param contract as the chips.
  class AccountBreakdown
    Row = Struct.new(:account, :amount_cents, :count, keyword_init: true) do
      def amount = Money.new(amount_cents, "PLN")
    end

    def self.call(scope)
      pluck = scope.spend
                   .group(:bank_account_id)
                   .order(Arel.sql("SUM(amount_cents) DESC"))
                   .pluck(Arel.sql("bank_account_id, SUM(amount_cents), COUNT(*)"))

      accounts = BankAccount.where(id: pluck.map(&:first)).index_by(&:id)

      pluck.filter_map do |account_id, sum, count|
        account = accounts[account_id]
        next nil unless account
        Row.new(account: account, amount_cents: sum.to_i, count: count.to_i)
      end
    end
  end
end
