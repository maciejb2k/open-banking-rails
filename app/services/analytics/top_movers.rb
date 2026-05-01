# frozen_string_literal: true

module Analytics
  # Categories whose spend changed the most vs. the previous period of
  # the same length. Answers the dashboard's "what changed?" question —
  # without it the user has to eyeball deltas across the bar chart.
  #
  # Operates on already-computed SpendBreakdown rows (with
  # `prev_amount_cents` attached) instead of re-querying — saves a round
  # trip and guarantees the panel and the bar chart see identical
  # numbers.
  #
  # Filtering rules (so the panel surfaces signal, not noise):
  #   * skip rows where neither side reached `min_amount_cents` —
  #     a category that went from 12 zł to 35 zł is technically +191%
  #     but uninteresting at the dashboard level.
  #   * skip rows whose absolute change is below `min_change_cents` —
  #     same reasoning, but anchored on swing magnitude.
  class TopMovers
    Row = Struct.new(:path, :name, :slug, :current_cents, :prev_cents, :delta_cents, :delta_pct, :currency, keyword_init: true) do
      def current_amount = Money.new(current_cents, currency)
      def prev_amount    = Money.new(prev_cents, currency)
      def delta_amount   = Money.new(delta_cents.abs, currency)
      def direction      = delta_cents >= 0 ? :up : :down
      # New spending (no previous activity) — the "+%" is undefined; UI
      # surfaces a "new" badge instead of an arrow.
      def new_spend?     = prev_cents.zero? && current_cents.positive?
    end

    def self.from_breakdown(breakdown, limit: 5, min_amount_cents: 5_000, min_change_cents: 5_000)
      breakdown.filter_map do |row|
        prev_cents = row.prev_amount_cents.to_i
        delta_cents = row.amount_cents - prev_cents
        next if delta_cents.abs < min_change_cents
        next if [ row.amount_cents, prev_cents ].max < min_amount_cents

        Row.new(
          path:          row.path,
          name:          row.name,
          slug:          row.slug,
          current_cents: row.amount_cents,
          prev_cents:    prev_cents,
          delta_cents:   delta_cents,
          delta_pct:     row.delta_pct,
          currency:      row.currency
        )
      end.sort_by { |r| -r.delta_cents.abs }.first(limit)
    end
  end
end
