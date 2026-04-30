# frozen_string_literal: true

module Analytics
  # A bounded date range with a bucket granularity for time-series queries.
  #
  # Used by every analytics service that needs to:
  #   * narrow a relation to a time window (`from..to`)
  #   * group by day / week / month, with empty buckets filled to zero
  #   * compare against an immediately-preceding window of the same length
  #
  # Gap-fill is intentionally Ruby-side, not SQL `generate_series` — at
  # personal-app scale the difference is microseconds, and pushing it into
  # SQL means every aggregation duplicates the same bucket-skeleton CTE.
  # The single Ruby helper (`fill`) is the wrapper for all charts.
  class Period
    BUCKETS = %i[day week month].freeze

    # Inclusive on both ends. Default bucket :day matches the MVP1 dashboard
    # (30-day window, 30 points). Day/week/month switch follows when longer
    # windows are added — the helper is here, but the dispatcher is not.
    def self.last_n_days(n, bucket: :day)
      to = Date.current
      new(from: to - (n - 1).days, to: to, bucket: bucket)
    end

    attr_reader :from, :to, :bucket

    def initialize(from:, to:, bucket: :day)
      raise ArgumentError, "bucket must be one of #{BUCKETS}" unless BUCKETS.include?(bucket)
      raise ArgumentError, "from must be <= to" if from > to
      @from, @to, @bucket = from, to, bucket
    end

    def range = from..to
    def length_days = (to - from).to_i + 1

    # Same length, ending the day before `from`. Symmetric so any sum on
    # `previous` is directly comparable to the same sum on `self`.
    def previous
      self.class.new(from: from - length_days.days, to: from - 1.day, bucket: bucket)
    end

    # Every bucket-start in the range, in chronological order. Source of
    # truth for gap-filling — chart x-axes iterate this, never the data.
    def buckets
      case bucket
      when :day   then (from..to).to_a
      when :week  then step_by_weeks
      when :month then step_by_months
      end
    end

    # Given { Date => value } (where Date is a bucket-start), returns
    # [{ bucket: Date, value: x }] in bucket order with `default` filling
    # gaps. Charts consume this directly.
    def fill(series, default: 0)
      buckets.map { |b| { bucket: b, value: series.fetch(b, default) } }
    end

    # PG expression that maps a date column to its bucket-start. Use in
    # GROUP BY when you need the database to bucket for you.
    def date_trunc_sql(column = "booking_date")
      "DATE_TRUNC('#{bucket}', #{column})::date"
    end

    private

    def step_by_weeks
      cursor = from.beginning_of_week
      [].tap do |out|
        while cursor <= to
          out << cursor
          cursor += 7
        end
      end
    end

    def step_by_months
      cursor = from.beginning_of_month
      [].tap do |out|
        while cursor <= to
          out << cursor
          cursor = cursor.next_month
        end
      end
    end
  end
end
