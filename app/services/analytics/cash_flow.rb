# frozen_string_literal: true

module Analytics
  # Net cash flow over a Period — the time-series the user looks at first
  # ("ile wpłynęło, ile wypłynęło, kiedy"). Returns spend and income
  # separately per bucket so the chart can render paired bars (income up,
  # spend up alongside) and the caller can derive net = income − spend.
  #
  # Partition: spend + income only. Transfers cancel against themselves
  # across own accounts and would smear the line; savings + ignored are
  # explicitly off-balance for "what hit my available money". Same
  # partitioning rule as everywhere — Category#kind first.
  class CashFlow
    Point = Struct.new(:date, :spend_cents, :income_cents, keyword_init: true) do
      def net_cents    = income_cents - spend_cents
      # Back-compat alias — callers reading `.amount_cents` (e.g.
      # "biggest day" lookup) still get net flow.
      def amount_cents = net_cents
      def amount       = Money.new(net_cents, "PLN")
      def positive?    = net_cents.positive?
      def quiet?       = spend_cents.zero? && income_cents.zero?
    end

    # Bucketed spend + income series, gap-filled to zero on quiet
    # buckets. Bucket granularity comes from `period.bucket` (day/week/
    # month) — the SQL `DATE_TRUNC` switches via `period.date_trunc_sql`,
    # so the same query shape works for all three.
    def self.series(scope, period:)
      spend_by  = bucketed_sum(scope.spend, period)
      income_by = bucketed_sum(scope.income, period)

      period.buckets.map do |b|
        Point.new(date: b, spend_cents: spend_by.fetch(b, 0), income_cents: income_by.fetch(b, 0))
      end
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

    def self.bucketed_sum(relation, period)
      relation.group(period.date_trunc_sql)
              .sum(:amount_cents)
              .transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k.to_date }
    end
    private_class_method :bucketed_sum
  end
end
