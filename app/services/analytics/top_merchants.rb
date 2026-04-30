# frozen_string_literal: true

module Analytics
  # Top merchants by spend within a scope. Renders into the breakdown
  # list widget on the dashboard and into "merchants in this category"
  # on the category drill-down (different scope, same shape).
  #
  # Excludes rows without a merchant — those go into a separate
  # "merchantless" surface (LLM enrichment review queue), not into the
  # analytics top-list.
  class TopMerchants
    Row = Struct.new(:merchant, :amount_cents, :count, keyword_init: true) do
      def amount = Money.new(amount_cents, "PLN")
    end

    def self.call(scope, limit: 8)
      pluck = scope.spend
                   .where.not(merchant_id: nil)
                   .group(:merchant_id)
                   .order(Arel.sql("SUM(amount_cents) DESC"))
                   .limit(limit)
                   .pluck(Arel.sql("merchant_id, SUM(amount_cents), COUNT(*)"))

      merchants = Merchant.where(id: pluck.map(&:first)).index_by(&:id)

      pluck.filter_map do |merchant_id, sum, count|
        merchant = merchants[merchant_id]
        next nil unless merchant
        Row.new(merchant: merchant, amount_cents: sum.to_i, count: count.to_i)
      end
    end
  end
end
