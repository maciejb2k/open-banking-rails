# frozen_string_literal: true

module Recurrence
  # Detects cyclical charges from transaction history and writes the
  # `recurring` / `recurrence_interval` flags onto TransactionEnrichment.
  #
  # No library exists for this in Ruby — the heuristic is small enough to
  # own. Layer 2 facet: independent of category, merchant, and source.
  #
  # Algorithm (per merchant):
  #   1. Look at this merchant's last `lookback_days` of debit charges
  #      (spend only — refunds/credits don't establish recurrence).
  #   2. Need ≥ MIN_OCCURRENCES bookings to claim a pattern.
  #   3. Compute consecutive interval deltas in days; the median tells us
  #      the candidate cadence.
  #   4. Confirm it: ≥ MIN_OCCURRENCES of those deltas fall into the
  #      tolerance band of one of the canonical buckets (weekly / monthly
  #      / yearly).
  #   5. Confirm amount stability: the merchant's amount stddev / mean
  #      ratio (CV) is ≤ AMOUNT_CV_MAX. Recurring charges are typically
  #      flat-fee within a small range; one-offs swing wildly.
  #   6. Set `recurring=true, recurrence_interval=<bucket>` on every
  #      enrichment for that merchant within the lookback window where
  #      `category_overridden` is false (don't override user decisions).
  #
  # Manual rows are also touched — the user signs up for a subscription
  # via cash too. Source-rule classifications stay; only the Layer 2
  # property is updated.
  class Detector
    MIN_OCCURRENCES  = 3
    AMOUNT_CV_MAX    = 0.30      # < 30 % coefficient of variation
    INTERVAL_BUCKETS = {
      "weekly"  => (5..9),       # 7 ± 2
      "monthly" => (26..34),     # 30 ± 4 (covers 28/29/30/31-day months)
      "yearly"  => (358..372)    # 365 ± 7
    }.freeze

    def self.call(user:, lookback_days: 365)
      new(user: user, lookback_days: lookback_days).call
    end

    def initialize(user:, lookback_days:)
      @user, @lookback_days = user, lookback_days
    end

    def call
      stats = Hash.new(0)
      window_start = @lookback_days.days.ago.to_date

      grouped_charges.each do |merchant_id, charges|
        next stats[:skipped_short] += 1 if charges.size < MIN_OCCURRENCES

        interval = infer_interval(charges)
        next stats[:skipped_irregular] += 1 unless interval

        next stats[:skipped_unstable] += 1 unless amount_stable?(charges)

        # Apply: every enrichment for this merchant in the window where
        # the user hasn't manually decided on the recurrence flag.
        ids = enrichment_ids_for(merchant_id, window_start)
        TransactionEnrichment.where(id: ids).update_all(
          recurring: true,
          recurrence_interval: interval
        )
        stats[interval.to_sym] += ids.size
      end

      stats
    end

    private

    # All spend charges in lookback window, grouped by merchant. We pull
    # straight from LedgerEntry (the view) to honour the same partitioning
    # as the dashboard — and so a misclassified income credit can't
    # accidentally establish a "monthly" pattern.
    def grouped_charges
      window_start = @lookback_days.days.ago.to_date
      LedgerEntry.for_user(@user).booked.spend
                 .where("booking_date >= ?", window_start)
                 .where.not(merchant_id: nil)
                 .order(:booking_date)
                 .pluck(:merchant_id, :booking_date, :amount_cents)
                 .group_by(&:first)
                 .transform_values { |rows| rows.map { |_, date, cents| [ date, cents ] } }
    end

    def infer_interval(charges)
      dates  = charges.map(&:first)
      deltas = dates.each_cons(2).map { |a, b| (b - a).to_i }
      return nil if deltas.empty?

      INTERVAL_BUCKETS.each do |label, range|
        hits = deltas.count { |d| range.cover?(d) }
        return label if hits >= MIN_OCCURRENCES - 1   # n-1 deltas for n charges
      end
      nil
    end

    def amount_stable?(charges)
      cents = charges.map(&:last)
      mean = cents.sum.to_f / cents.size
      return true  if mean.zero?
      var  = cents.sum { |c| (c - mean)**2 } / cents.size
      cv   = Math.sqrt(var) / mean
      cv <= AMOUNT_CV_MAX
    end

    # Enrichment ids for this merchant within the window — both bank and
    # manual side, untouched by user override. We don't go via LedgerEntry
    # because it's a view (no UPDATE); reach back to the source records'
    # enrichments directly.
    def enrichment_ids_for(merchant_id, window_start)
      TransactionEnrichment
        .for_user(@user)
        .where(merchant_id: merchant_id, category_overridden: false)
        .where.not(source: "manual")
        .joins(
          "INNER JOIN bank_transactions bt ON " \
          "(transaction_enrichments.enrichable_type = 'BankTransaction' AND transaction_enrichments.enrichable_id = bt.id)"
        )
        .where("bt.booking_date >= ?", window_start)
        .pluck(:id)
    end
  end
end
