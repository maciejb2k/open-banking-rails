# frozen_string_literal: true

module Analytics
  # Builds the deterministic fact set that AiInsight serializes into the
  # LLM prompt. Every number in the model's output must come from here
  # (NumericGuard enforces this).
  #
  # Numbers are intentionally pre-rounded to integers (PLN, %): a person
  # saying "wydałeś 4523 zł, o 14% więcej niż wcześniej" doesn't carry
  # cents or fractional percent, so the LLM doesn't either — and the
  # numeric guard doesn't have to worry about "4523" vs "4523.10".
  class FactsBuilder
    NOTABLE_MIN_DELTA_PCT = 100.0
    NOTABLE_MIN_AMOUNT_PLN = 200.0

    def initialize(filter:)
      @filter = filter
    end

    def call
      spend_total      = total_pln(@filter.scope)
      spend_prev       = total_pln(@filter.previous_scope)
      delta_pct        = pct_delta(spend_total, spend_prev)

      top_category     = build_top_category(spend_total)
      top_merchant_row = build_top_merchant(spend_total)
      movers           = build_notable_movers(spend_total)

      {
        period_label:        period_label,
        period_days:         @filter.period.length_days,
        account_count:       @filter.account_ids.size,
        spend_total_pln:     spend_total.round,
        prev_period_spend_pln: spend_prev.zero? ? nil : spend_prev.round,
        spend_delta_pct:     delta_pct,
        top_category:        top_category,
        top_merchant:        top_merchant_row,
        notable_movers:      movers
      }.compact
    end

    private

    def total_pln(scope)
      cents = scope.spend.where(currency: "PLN").sum(:amount_cents)
      cents / 100.0
    end

    def period_label
      "ostatnie #{@filter.period.length_days} dni"
    end

    def build_top_category(spend_total)
      row = SpendBreakdown.by_category(@filter.scope, user: @filter.user).first
      return nil unless row && spend_total.positive?

      prev_amount = SpendBreakdown
                      .by_category(@filter.previous_scope, user: @filter.user)
                      .find { |r| r.category.id == row.category.id }
                      &.amount_cents.to_i / 100.0

      {
        name:       row.category.name,
        amount_pln: (row.amount_cents / 100.0).round,
        share_pct:  ((row.amount_cents / 100.0 / spend_total) * 100).round,
        delta_pct:  pct_delta(row.amount_cents / 100.0, prev_amount)
      }.compact
    end

    def build_top_merchant(spend_total)
      row = @filter.scope.spend
                   .where.not(merchant_id: nil)
                   .group(:merchant_id)
                   .order(Arel.sql("SUM(amount_cents) DESC"))
                   .limit(1)
                   .pluck(Arel.sql("merchant_id, SUM(amount_cents), COUNT(*)"))
                   .first
      return nil unless row && spend_total.positive?

      merchant_id, sum_cents, count = row
      merchant = @filter.user.merchants.find_by(id: merchant_id)
      return nil unless merchant

      prev_cents = @filter.previous_scope.spend
                          .where(merchant_id: merchant_id)
                          .sum(:amount_cents)

      {
        name:       merchant.display,
        amount_pln: (sum_cents / 100.0).round,
        count:      count.to_i,
        delta_pct:  pct_delta(sum_cents / 100.0, prev_cents / 100.0)
      }.compact
    end

    # Categories whose spend swung by ≥100% AND ≥ 200 PLN absolute. 0..2
    # entries — anything more crowds the 3-sentence narration.
    def build_notable_movers(_spend_total)
      current = SpendBreakdown.by_category(@filter.scope, user: @filter.user).index_by { |r| r.category.id }
      previous_rows = SpendBreakdown.by_category(@filter.previous_scope, user: @filter.user).index_by { |r| r.category.id }

      ids = (current.keys + previous_rows.keys).uniq

      ids.filter_map do |cat_id|
        cur_amount = (current[cat_id]&.amount_cents.to_i) / 100.0
        prev_amount = (previous_rows[cat_id]&.amount_cents.to_i) / 100.0
        delta = pct_delta(cur_amount, prev_amount)
        next nil unless delta && delta.abs >= NOTABLE_MIN_DELTA_PCT
        next nil unless cur_amount >= NOTABLE_MIN_AMOUNT_PLN || prev_amount >= NOTABLE_MIN_AMOUNT_PLN

        ref = current[cat_id] || previous_rows[cat_id]
        {
          kind:            "category",
          name:            ref.category.name,
          amount_pln:      cur_amount.round,
          prev_amount_pln: prev_amount.round,
          delta_pct:       delta
        }
      end.sort_by { |m| -m[:delta_pct].abs }.first(2)
    end

    # Returns nil when prev is zero (delta undefined / infinite). Caller
    # treats nil as "no comparison available" — never an inflated %.
    def pct_delta(current, prev)
      return nil if prev.nil? || prev.zero?
      (((current - prev) / prev) * 100).round
    end
  end
end
