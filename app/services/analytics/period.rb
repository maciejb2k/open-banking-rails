# frozen_string_literal: true

module Analytics
  # Gap-fill is intentionally Ruby-side, not SQL `generate_series` - at
  # personal-app scale the difference is microseconds, and the single Ruby
  # helper (`fill`) keeps every aggregation from duplicating a CTE.
  class Period
    BUCKETS = %i[day week month].freeze

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

    def previous
      self.class.new(from: from - length_days.days, to: from - 1.day, bucket: bucket)
    end

    def buckets
      case bucket
      when :day   then (from..to).to_a
      when :week  then step_by_weeks
      when :month then step_by_months
      end
    end

    def fill(series, default: 0)
      buckets.map { |b| { bucket: b, value: series.fetch(b, default) } }
    end

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
