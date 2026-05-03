# frozen_string_literal: true

module Analytics
  # Spend + income only - transfers cancel across own accounts and would smear
  # the line; savings + ignored are off-balance for "what hit my available money".
  class CashFlow
    Point = Struct.new(:date, :spend_cents, :income_cents, :currency, keyword_init: true) do
      def net_cents    = income_cents - spend_cents
      # Back-compat alias - callers reading `.amount_cents` still get net flow.
      def amount_cents = net_cents
      def amount       = Money.new(net_cents, currency)
      def positive?    = net_cents.positive?
      def quiet?       = spend_cents.zero? && income_cents.zero?
    end

    def self.series(scope, period:, currency:)
      spend_by  = bucketed_sum(scope.spend, period)
      income_by = bucketed_sum(scope.income, period)

      period.buckets.map do |b|
        Point.new(date: b, spend_cents: spend_by.fetch(b, 0), income_cents: income_by.fetch(b, 0), currency: currency)
      end
    end

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
