# frozen_string_literal: true

module Analytics
  # Defaults: all owned accounts + month-to-date period. Account-isolation
  # is guaranteed - we always intersect with the user's owned accounts.
  class Filter
    attr_reader :user

    def initialize(user:, params:)
      @user, @params = user, params
    end

    # Sentinel `?accounts=none` = "explicitly empty" (every chip off, charts
    # show 0). Without this, an empty `account_ids[]` would collapse into
    # the default and we'd never get a true zero state.
    def none?
      @params[:accounts].to_s == "none"
    end

    def explicit_account_ids
      @explicit_account_ids ||= begin
        return [] if none?
        requested = Array(@params[:account_ids]).map(&:to_i).reject(&:zero?)
        requested & @user.all_bank_account_ids
      end
    end

    def account_ids
      return [] if none?
      explicit_account_ids.presence || @user.all_bank_account_ids
    end

    # Distinct from `none?` (which means zero accounts).
    def all_accounts?
      !none? && explicit_account_ids.empty?
    end

    def period
      @period ||= Period.new(from: from_date, to: to_date, bucket: bucket)
    end

    def bucket
      @bucket ||= bucket_explicit? ? @params[:bucket].to_sym : default_bucket_for_length
    end

    def bucket_explicit?
      Period::BUCKETS.include?(@params[:bucket].to_s.to_sym)
    end

    # Cross-currency sums are nonsense without FX conversion (no MVP),
    # so every aggregate is single-currency. Defaults to the user's
    # dominant currency.
    def currency
      @currency ||= currency_explicit? ? @params[:currency].to_s.upcase : dominant_currency
    end

    def currency_explicit?
      iso = @params[:currency].to_s.upcase
      iso.present? && available_currencies.include?(iso)
    end

    def available_currencies
      @available_currencies ||= LedgerEntry
                                  .where(bank_account_id: @user.all_bank_account_ids)
                                  .distinct.pluck(:currency).compact.sort
    end

    # Booked only - pending rows double-count once they settle.
    def scope
      base = LedgerEntry.where(bank_account_id: account_ids)
                        .where(currency: currency)
                        .booked.in_range(period.from, period.to)
      under_path.present? ? base.under_path(under_path) : base
    end

    def previous_scope
      from_d, to_d = previous_range
      base = LedgerEntry.where(bank_account_id: account_ids)
                        .where(currency: currency)
                        .booked.in_range(from_d, to_d)
      under_path.present? ? base.under_path(under_path) : base
    end

    # For month-aligned periods, shift by a calendar month (not N days) so
    # "this month vs last month" reads correctly. Day-based presets stay
    # symmetric and fall through to Period#previous.
    def previous_range
      if full_calendar_month?
        # Compare full month vs full month - Mar has 31 days, Apr has 30.
        prev_from = period.from << 1
        [ prev_from, prev_from.end_of_month ]
      elsif month_to_date?
        # Cap at end_of_prev_month for short months: May 31 → Apr 30.
        prev_from        = period.from << 1
        prev_to_offset   = prev_from + (period.length_days - 1).days
        prev_to          = [ prev_to_offset, prev_from.end_of_month ].min
        [ prev_from, prev_to ]
      else
        prev = period.previous
        [ prev.from, prev.to ]
      end
    end

    def month_to_date?
      period.from == Date.current.beginning_of_month && period.to == Date.current
    end

    def full_calendar_month?
      period.from == period.from.beginning_of_month &&
        period.to   == period.from.end_of_month
    end

    def previous_full_month_scope
      return nil unless month_to_date?
      prev_from = (Date.current << 1).beginning_of_month
      prev_to   = (Date.current << 1).end_of_month
      base = LedgerEntry.where(bank_account_id: account_ids)
                        .where(currency: currency)
                        .booked.in_range(prev_from, prev_to)
      under_path.present? ? base.under_path(under_path) : base
    end

    def previous_label
      if full_calendar_month?
        "vs #{(period.from << 1).strftime('%b %Y')}"
      elsif month_to_date?
        prev_from, prev_to = previous_range
        "vs #{prev_from.strftime('%b')} #{prev_from.day}–#{prev_to.day}"
      else
        "vs previous #{period.length_days} days"
      end
    end

    def under_path
      @under_path ||= @params[:under_path].to_s.presence
    end

    def root_path
      under_path&.split(".")&.first
    end

    def aggregation_depth
      return 1 if under_path.blank?
      under_path.count(".") + 2
    end

    # Default state (all accounts) emits neither `accounts` nor `account_ids[]`
    # so a passive click (e.g. period preset) doesn't promote default → explicit.
    # `bucket` is emitted only when explicitly picked, so changing period lets
    # the smart default reapply for the new length.
    def to_query_params
      params = { from: period.from.iso8601, to: period.to.iso8601 }
      params[:bucket] = bucket if bucket_explicit?
      params[:currency] = currency if currency_explicit?
      params[:under_path] = under_path if under_path.present?
      if none?
        params[:accounts] = "none"
      elsif explicit_account_ids.any?
        params[:account_ids] = explicit_account_ids
      end
      params
    end

    private

    def dominant_currency
      @dominant_currency ||= LedgerEntry
                               .where(bank_account_id: @user.all_bank_account_ids)
                               .group(:currency)
                               .order(Arel.sql("COUNT(*) DESC"))
                               .limit(1)
                               .pluck(:currency)
                               .first || "PLN"
    end

    def from_date
      @from_date ||= if @params[:from].present? && @params[:to].present?
                       parse_date(@params[:from])
      else
                       Date.current.beginning_of_month
      end
    end

    def to_date
      @to_date ||= if @params[:from].present? && @params[:to].present?
                     parse_date(@params[:to])
      else
                     Date.current
      end
    end

    # Resolve without touching `period` - period itself depends on bucket.
    def default_bucket_for_length
      days = (to_date - from_date).to_i + 1
      case days
      when 0..31    then :day
      when 32..180  then :week
      else               :month
      end
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      Date.current
    end
  end
end
