# frozen_string_literal: true

module Analytics
  # Spend aggregations on top of a scoped LedgerEntry relation.
  #
  # All entry points partition on `Category#kind = 'expense'` via
  # `LedgerEntry.spend` — never sum raw amounts (income cancels expense,
  # transfers double-count). amount_cents is non-negative on the view; we
  # report magnitude (people read spend as a positive number).
  #
  # Layer 1 (path) groupings: `by_category` aggregates by the category
  # path's prefix at the requested depth (default = 1 = top-level domain).
  # Drill-down into a subtree uses `by_subpath(under:)` which exposes the
  # next level under a given root. Both are powered by the GiST-indexed
  # `category_path` (ltree) projected by the `ledger_entries` view.
  class SpendBreakdown
    Row = Struct.new(:path, :name, :merchant, :amount_cents, :prev_amount_cents, :count, :currency, keyword_init: true) do
      def amount = Money.new(amount_cents, currency)
      def prev_amount = Money.new(prev_amount_cents.to_i, currency)
      def slug = path.to_s.tr(".", "_")

      def delta_pct
        return nil if prev_amount_cents.nil? || prev_amount_cents.zero?
        (((amount_cents - prev_amount_cents).to_f / prev_amount_cents) * 100).round
      end
    end

    # Total expense in cents, single number. Caller wraps in Money.
    def self.total_cents(scope)
      scope.spend.sum(:amount_cents)
    end

    # Group by category path. Default = full leaf granularity (each
    # distinct path gets its own row), matching v01's "one bar per
    # category" semantics. Optionally roll up to a fixed depth — useful
    # for a "spend by domain" overview alongside the detailed chart.
    #
    #   depth: nil → group by full path (every leaf is its own row)
    #   depth: 1   → roll up to top-level domains ("food", "lifestyle"…)
    #   depth: 2   → roll up to mid-level ("food.cooking", "food.eating_out"…)
    #
    # Pass `previous_scope:` for delta-vs-previous; pass `user:` so the
    # path → display-name hydration uses the user's own categories.
    def self.by_category(scope, user:, currency:, depth: nil, previous_scope: nil)
      rows = bucket_by_path(scope.spend, depth, currency)
      hydrate_names!(rows, user: user)

      if previous_scope
        prev = bucket_by_path(previous_scope.spend, depth, currency).index_by(&:path)
        rows.each { |r| r.prev_amount_cents = prev[r.path]&.amount_cents.to_i }
      end

      rows.sort_by { |r| -r.amount_cents }
    end

    # Drill-down: rows directly under `under` (single-segment expansion).
    # `under` accepts either a Category or a path string. Returns rows
    # at depth = under.depth + 1 within that subtree only.
    def self.by_subpath(scope, under:, user:, currency:)
      under_path = under.is_a?(Category) ? under.path.to_s : under.to_s
      depth = under_path.count(".") + 2  # next level down (1-indexed in subpath)

      narrowed = scope.spend.under_path(under_path)
      rows = bucket_by_path(narrowed, depth, currency)
      hydrate_names!(rows, user: user)
      rows.sort_by { |r| -r.amount_cents }
    end

    # [{ merchant:, amount_cents:, count: }] for a single category subtree,
    # sorted DESC. `category` here is interpreted as a subtree root — pass
    # any category, get its descendants too. Unmatched (merchant_id IS NULL
    # but category was assigned via category_override) bucket is grouped
    # under a sentinel.
    def self.by_merchant_in_category(scope, category, user:, currency:)
      pluck = scope.spend
                   .under_path(category)
                   .group(:merchant_id)
                   .pluck(Arel.sql("merchant_id, SUM(amount_cents), COUNT(*)"))

      merchants = user.merchants.where(id: pluck.map(&:first).compact).index_by(&:id)

      pluck.map do |merchant_id, sum, count|
        merchant = merchant_id && merchants[merchant_id]
        Row.new(
          path:         category.is_a?(Category) ? category.path.to_s : category.to_s,
          name:         merchant&.display,
          merchant:     merchant,
          amount_cents: sum.to_i,
          count:        count.to_i,
          currency:     currency
        )
      end.sort_by { |r| -r.amount_cents }
    end

    # 12-month trend for a single merchant, gap-filled. Always last 12 months
    # ending today (independent of the dashboard period — drill-down trend
    # is always "history of this merchant", not "this merchant in selected
    # window"). Currency-scoped to keep the same partitioning rule as the
    # dashboard — a merchant charged in EUR shouldn't smear into a PLN trend.
    def self.merchant_monthly_trend(user:, merchant_id:, currency:, months: 12)
      from = (months - 1).months.ago.beginning_of_month.to_date
      period = Period.new(from: from, to: Date.current, bucket: :month)

      raw = LedgerEntry.where(bank_account_id: user.all_bank_account_ids)
                       .where(currency: currency)
                       .booked.spend
                       .where(merchant_id: merchant_id)
                       .in_range(period.from, period.to)
                       .group(period.date_trunc_sql)
                       .sum(:amount_cents)
                       .transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k.to_date }

      period.fill(raw)
    end

    # Bucket rows by category path. With `depth: nil` (default), groups
    # by the full path — one row per distinct leaf. With a depth value,
    # rolls up to that prefix using PG's `subpath` so a row at
    # `food.cooking.bakery` collapses into `food.cooking` at depth=2.
    # Rows whose `category_path` is NULL (unmatched) are excluded —
    # they belong on a "needs review" surface, not the spend chart.
    def self.bucket_by_path(relation, depth, currency)
      grouping_sql = depth ? "subpath(category_path, 0, #{depth.to_i})::text" : "category_path::text"
      base = relation.where.not(category_path: nil)
      base = base.where("nlevel(category_path) >= ?", depth) if depth
      base.group(Arel.sql(grouping_sql))
          .pluck(Arel.sql("#{grouping_sql}, SUM(amount_cents), COUNT(*)"))
          .map { |path, sum, count| Row.new(path: path, amount_cents: sum.to_i, count: count.to_i, currency: currency) }
    end
    private_class_method :bucket_by_path

    # The bucket-by-path result keys are paths, not category ids — we
    # find the matching Category record by `path =` and pull its `name`.
    # When the user later renames a category, the bar relabels without
    # any code change. If a path doesn't match a category (shouldn't
    # happen — every path should exist), we fall back to a title-cased
    # version of the leaf segment.
    def self.hydrate_names!(rows, user:)
      paths = rows.map(&:path)
      cats = user.categories.where(path: paths).index_by { |c| c.path.to_s }
      rows.each do |row|
        cat = cats[row.path]
        row.name = cat&.name || row.path.split(".").last.tr("_", " ").titleize
      end
    end
    private_class_method :hydrate_names!
  end
end
