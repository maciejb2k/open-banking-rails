# frozen_string_literal: true

module Analytics
  class TopMerchants
    Row = Struct.new(:merchant, :amount_cents, :count, :currency, keyword_init: true) do
      def amount = Money.new(amount_cents, currency)
    end

    def self.call(scope, user:, currency:, limit: 8)
      pluck = scope.spend
                   .where.not(merchant_id: nil)
                   .group(:merchant_id)
                   .order(Arel.sql("SUM(amount_cents) DESC"))
                   .limit(limit)
                   .pluck(Arel.sql("merchant_id, SUM(amount_cents), COUNT(*)"))

      merchants = user.merchants.where(id: pluck.map(&:first)).index_by(&:id)

      pluck.filter_map do |merchant_id, sum, count|
        merchant = merchants[merchant_id]
        next nil unless merchant
        Row.new(merchant: merchant, amount_cents: sum.to_i, count: count.to_i, currency: currency)
      end
    end
  end
end
