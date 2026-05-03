# frozen_string_literal: true

module Recurrence
  # Per merchant: ≥ MIN_OCCURRENCES debit charges, interval deltas mostly fall
  # in one of the canonical buckets, and amount CV (stddev/mean) ≤
  # AMOUNT_CV_MAX. Spend only - refunds/credits don't establish recurrence.
  # Skips category-overridden rows.
  class Detector
    MIN_OCCURRENCES  = 3
    AMOUNT_CV_MAX    = 0.30
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

    # Pull from LedgerEntry so a misclassified income credit can't establish
    # a pattern.
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
        return label if hits >= MIN_OCCURRENCES - 1
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

    # Reach back to source records' enrichments - LedgerEntry is a view, no UPDATE.
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
