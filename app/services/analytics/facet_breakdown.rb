# frozen_string_literal: true

module Analytics
  # Layer 2 aggregations — the orthogonal axes that hierarchy can't
  # express. Each method returns a 2-row breakdown so the dashboard can
  # render a paired bar (or stacked card) without further math.
  #
  # All methods consume an already-scoped LedgerEntry relation (typically
  # `Analytics::Filter#scope`) and partition through `.spend` first.
  # Income / transfers / savings need different lenses — those go on
  # CashFlow, not here.
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

    # Essentials vs discretionary. THE personal-finance KPI — what % of
    # spend is needs vs wants. Nil-safe at zero spend.
    def self.essential(scope, currency:)
      ess = scope.spend.essential
      dis = scope.spend.discretionary
      Pair.new(
        left:  Row.new(label: "Essential",     amount_cents: ess.sum(:amount_cents), count: ess.count, currency: currency),
        right: Row.new(label: "Discretionary", amount_cents: dis.sum(:amount_cents), count: dis.count, currency: currency),
        currency: currency
      )
    end

    # Recurring vs one-off. Recurring is detected by Recurrence::Detector
    # and stored on transaction_enrichments; the view surfaces it.
    # "Recurring" answers "ile mnie kosztują stałe zobowiązania" without
    # forcing them into a synthetic `subscriptions` category.
    def self.recurring(scope, currency:)
      rec = scope.spend.recurring
      one = scope.spend.one_off
      Pair.new(
        left:  Row.new(label: "Recurring", amount_cents: rec.sum(:amount_cents), count: rec.count, currency: currency),
        right: Row.new(label: "One-off",   amount_cents: one.sum(:amount_cents), count: one.count, currency: currency),
        currency: currency
      )
    end

    # Recurring spend grouped by interval — gives the dashboard a
    # "you'll spend ~X/month on subscriptions" forecast number.
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
