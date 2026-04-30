# frozen_string_literal: true

module Analytics
  # Daily net cash flow over a Period — the time-series the user looks
  # at first ("ile wpłynęło, ile wypłynęło, kiedy"). Sums signed_amount
  # per day, gap-filled to zero on quiet days.
  #
  # Partition: spend + income only. Transfers cancel against themselves
  # across own accounts and would smear the line; savings + ignored are
  # explicitly off-balance for "what hit my available money". Same
  # partitioning rule as everywhere — Category#kind first.
  class CashFlow
    Point = Struct.new(:date, :amount_cents, keyword_init: true) do
      def amount = Money.new(amount_cents, "PLN")
      def positive? = amount_cents.positive?
    end

    def self.daily_series(scope, period:)
      raw = scope.joins(:effective_category)
                 .where(categories: { kind: %w[expense income] })
                 .group("DATE_TRUNC('day', booking_date)::date")
                 .sum(:signed_amount_cents)
                 .transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k.to_date }

      period.fill(raw, default: 0).map { |row| Point.new(date: row[:bucket], amount_cents: row[:value].to_i) }
    end

    # Aggregate stats for the stat-card row. Goes through `LedgerEntry`'s
    # direction-aware `.spend` / `.income` scopes — same source of truth
    # as every other widget, so a misclassified credit-with-expense-kind
    # can't inflate spend (or vice versa for income).
    def self.totals(scope)
      spend  = scope.spend.sum(:amount_cents)
      income = scope.income.sum(:amount_cents)
      {
        spend_cents:  spend,
        income_cents: income,
        net_cents:    income - spend
      }
    end
  end
end
