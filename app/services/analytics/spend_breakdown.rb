# frozen_string_literal: true

module Analytics
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

    def self.total_cents(scope)
      scope.spend.sum(:amount_cents)
    end

    # depth: nil → one row per leaf path; depth: 1 → top-level domains;
    # depth: 2 → mid-level (food.cooking …).
    def self.by_category(scope, user:, currency:, depth: nil, previous_scope: nil)
      rows = bucket_by_path(scope.spend, depth, currency)
      hydrate_names!(rows, user: user)

      if previous_scope
        prev = bucket_by_path(previous_scope.spend, depth, currency).index_by(&:path)
        rows.each { |r| r.prev_amount_cents = prev[r.path]&.amount_cents.to_i }
      end

      rows.sort_by { |r| -r.amount_cents }
    end

    def self.by_subpath(scope, under:, user:, currency:)
      under_path = under.is_a?(Category) ? under.path.to_s : under.to_s
      depth = under_path.count(".") + 2  # next level down (1-indexed in subpath)

      narrowed = scope.spend.under_path(under_path)
      rows = bucket_by_path(narrowed, depth, currency)
      hydrate_names!(rows, user: user)
      rows.sort_by { |r| -r.amount_cents }
    end

    # `category` is interpreted as a subtree root - descendants are included.
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

    # Always last 12 months ending today - drill-down trend is "history of
    # this merchant", not "this merchant in selected window".
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

    # Rows whose `category_path` is NULL (unmatched) are excluded - they
    # belong on a "needs review" surface, not the spend chart.
    def self.bucket_by_path(relation, depth, currency)
      grouping_sql = depth ? "subpath(category_path, 0, #{depth.to_i})::text" : "category_path::text"
      base = relation.where.not(category_path: nil)
      base = base.where("nlevel(category_path) >= ?", depth) if depth
      base.group(Arel.sql(grouping_sql))
          .pluck(Arel.sql("#{grouping_sql}, SUM(amount_cents), COUNT(*)"))
          .map { |path, sum, count| Row.new(path: path, amount_cents: sum.to_i, count: count.to_i, currency: currency) }
    end
    private_class_method :bucket_by_path

    # Look up by path so renames relabel without a code change. Falls back
    # to a title-cased leaf segment when a path doesn't match a category.
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
