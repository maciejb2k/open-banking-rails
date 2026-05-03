# frozen_string_literal: true

module Analytics
  # Filters out small categories (`min_amount_cents`) and small swings
  # (`min_change_cents`) so the panel surfaces signal, not noise.
  class TopMovers
    Row = Struct.new(:path, :name, :slug, :current_cents, :prev_cents, :delta_cents, :delta_pct, :currency, keyword_init: true) do
      def current_amount = Money.new(current_cents, currency)
      def prev_amount    = Money.new(prev_cents, currency)
      def delta_amount   = Money.new(delta_cents.abs, currency)
      def direction      = delta_cents >= 0 ? :up : :down
      # No previous activity - "+%" is undefined; UI surfaces a "new" badge.
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
