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
  end
end
