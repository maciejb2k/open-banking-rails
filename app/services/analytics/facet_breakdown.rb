# frozen_string_literal: true

module Analytics
  class FacetBreakdown
    Row = Struct.new(:label, :amount_cents, :count, :currency, keyword_init: true) do
      def amount = Money.new(amount_cents, currency)
    end

    Pair = Struct.new(:left, :right, :currency, keyword_init: true) do
      def total_cents       = left.amount_cents + right.amount_cents
      def total             = Money.new(total_cents, currency)
      def left_share_pct    = total_cents.zero? ? 0 : (left.amount_cents.to_f / total_cents * 100).round(1)
      def right_share_pct   = total_cents.zero? ? 0 : (right.amount_cents.to_f / total_cents * 100).round(1)
    end

    def self.essential(scope, currency:)
      ess = scope.spend.essential
      dis = scope.spend.discretionary
      Pair.new(
        left:  Row.new(label: "Essential",     amount_cents: ess.sum(:amount_cents), count: ess.count, currency: currency),
        right: Row.new(label: "Discretionary", amount_cents: dis.sum(:amount_cents), count: dis.count, currency: currency),
        currency: currency
      )
    end

    def self.recurring(scope, currency:)
      rec = scope.spend.recurring
      one = scope.spend.one_off
      Pair.new(
        left:  Row.new(label: "Recurring", amount_cents: rec.sum(:amount_cents), count: rec.count, currency: currency),
        right: Row.new(label: "One-off",   amount_cents: one.sum(:amount_cents), count: one.count, currency: currency),
        currency: currency
      )
    end

    def self.recurring_by_interval(scope, currency:)
      rows = scope.spend.recurring
                  .group(:recurrence_interval)
                  .pluck(Arel.sql("recurrence_interval, SUM(amount_cents), COUNT(*)"))
      rows.map { |interval, sum, count|
        Row.new(label: interval || "unknown", amount_cents: sum.to_i, count: count.to_i, currency: currency)
      }.sort_by { |r| -r.amount_cents }
    end
  end
end
