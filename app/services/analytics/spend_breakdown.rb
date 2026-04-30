# frozen_string_literal: true

module Analytics
  # Spend aggregations on top of a scoped LedgerEntry relation.
  #
  # All entry points partition on `Category#kind = 'expense'` via
  # `LedgerEntry.spend` — never sum raw amounts (income cancels expense,
  # transfers double-count). amount_cents is non-negative on the view; we
  # report magnitude (people read spend as a positive number).
  class SpendBreakdown
    Row = Struct.new(:category, :merchant, :amount_cents, :prev_amount_cents, :count, keyword_init: true) do
      def amount = Money.new(amount_cents, "PLN")
      def prev_amount = Money.new(prev_amount_cents.to_i, "PLN")

      def delta_pct
        return nil if prev_amount_cents.nil? || prev_amount_cents.zero?
        (((amount_cents - prev_amount_cents).to_f / prev_amount_cents) * 100).round
      end
    end

    # Total expense in cents, single number. Caller wraps in Money.
    def self.total_cents(scope)
      scope.spend.sum(:amount_cents)
    end

    # [{ category:, amount_cents:, count: }] sorted by amount DESC.
    # Pass `previous_scope:` to attach prev-period amounts on each row,
    # so the chart can render delta-vs-previous as a second dataset.
    # `user:` is required for hydrating slugs through the user's own
    # categories — defense-in-depth so a future cross-user scope leak in
    # the GROUP BY doesn't surface another user's category names.
    def self.by_category(scope, user:, previous_scope: nil)
      categorized = scope.spend
                         .group("categories.id", "categories.name", "categories.parent_id")
                         .pluck(Arel.sql("categories.id, categories.name, categories.parent_id, SUM(amount_cents), COUNT(*)"))
                         .map do |id, name, parent_id, sum, count|
        Row.new(
          category:     CategoryRef.new(id: id, name: name, parent_id: parent_id, slug: nil),
          amount_cents: sum.to_i,
          count:        count.to_i
        )
      end

      # Hydrate slugs from the user's own categories. If a foreign id
      # somehow slipped into the GROUP BY result, slug stays nil and the
      # row renders without a drill-down link.
      slugs = user.categories.where(id: categorized.map { |r| r.category.id }).pluck(:id, :slug).to_h
      categorized.each { |r| r.category.slug = slugs[r.category.id] }

      if previous_scope
        prev_sums = previous_scope.spend
                                  .group("categories.id")
                                  .sum(:amount_cents)
        categorized.each { |r| r.prev_amount_cents = prev_sums[r.category.id].to_i }
      end

      categorized.sort_by { |r| -r.amount_cents }
    end

    # [{ merchant:, amount_cents:, count: }] for a single category, sorted
    # DESC. Unmatched (merchant_id IS NULL but category was assigned via
    # category_override) bucket is grouped under a sentinel. `user:` scopes
    # the merchant hydration.
    def self.by_merchant_in_category(scope, category_id, user:)
      pluck = scope.spend
                   .where(effective_category_id: category_id)
                   .group(:merchant_id)
                   .pluck(Arel.sql("merchant_id, SUM(amount_cents), COUNT(*)"))

      merchants = user.merchants.where(id: pluck.map(&:first).compact).index_by(&:id)

      pluck.map do |merchant_id, sum, count|
        Row.new(
          merchant:     merchant_id ? merchants[merchant_id] : nil,
          amount_cents: sum.to_i,
          count:        count.to_i
        )
      end.sort_by { |r| -r.amount_cents }
    end

    # 12-month trend for a single merchant, gap-filled. Always last 12 months
    # ending today (independent of the dashboard period — drill-down trend
    # is always "history of this merchant", not "this merchant in selected
    # window").
    def self.merchant_monthly_trend(user:, merchant_id:, months: 12)
      from = (months - 1).months.ago.beginning_of_month.to_date
      period = Period.new(from: from, to: Date.current, bucket: :month)

      raw = LedgerEntry.where(bank_account_id: user.all_bank_account_ids)
                       .booked.spend
                       .where(merchant_id: merchant_id)
                       .in_range(period.from, period.to)
                       .group(period.date_trunc_sql)
                       .sum(:amount_cents)
                       .transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k.to_date }

      period.fill(raw)
    end

    # Lightweight hash-like ref so the breakdown row doesn't load an
    # ActiveRecord object per category just to read name/slug. Mutable so
    # we can attach slug after the GROUP BY pluck.
    CategoryRef = Struct.new(:id, :name, :parent_id, :slug, keyword_init: true)
  end
end
