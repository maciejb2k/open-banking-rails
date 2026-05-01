# frozen_string_literal: true

module Analytics
  # Parses dashboard URL params (`account_ids[]`, `from`, `to`) into a
  # scoped LedgerEntry relation + a Period, with sensible defaults.
  #
  # Defaults:
  #   * account_ids → all of the user's accounts (synced + cash wallets)
  #   * period      → last 30 days, day-bucketed
  #
  # Every analytics endpoint instantiates one of these and reads .scope /
  # .period / .to_query_params from it. Keeps param parsing in one place
  # and guarantees account-isolation (we always intersect with the user's
  # owned accounts, even if a stranger crafts ?account_ids=999).
  class Filter
    attr_reader :user

    def initialize(user:, params:)
      @user, @params = user, params
    end

    # Three states for account selection:
    #   * default     — no params, resolved to "all owned accounts"
    #   * narrowed    — explicit list of >= 1 account ids
    #   * none        — sentinel `?accounts=none` for "explicitly empty"
    #                   (user toggled every chip off; charts show 0)
    # `none` and `default` are visually different but resolve to different
    # scopes — without the sentinel, an empty `account_ids[]` would
    # collapse into the default and we'd never get a true zero state.
    def none?
      @params[:accounts].to_s == "none"
    end

    # User-explicit narrow (intersected with what they actually own to
    # neutralise crafted ?account_ids=999).
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

    # True when the filter is at its default (every account included,
    # no narrowing). Distinct from `none?` (= zero accounts).
    def all_accounts?
      !none? && explicit_account_ids.empty?
    end

    def period
      @period ||= Period.new(from: from_date, to: to_date, bucket: bucket)
    end

    # Time-series granularity (day / week / month). Explicit ?bucket=
    # wins; otherwise resolved from period length so 365d defaults to
    # monthly bars and 7d to daily, matching what's actually readable.
    def bucket
      @bucket ||= bucket_explicit? ? @params[:bucket].to_sym : default_bucket_for_length
    end

    def bucket_explicit?
      Period::BUCKETS.include?(@params[:bucket].to_s.to_sym)
    end

    # Reporting currency — every aggregate the dashboard renders is summed
    # in this currency only. Cross-currency sums are nonsense without FX
    # conversion (which we deliberately don't do at MVP). Explicit
    # ?currency= wins; otherwise we pick the user's dominant currency
    # (most rows in the ledger), falling back to PLN for an empty user.
    def currency
      @currency ||= currency_explicit? ? @params[:currency].to_s.upcase : dominant_currency
    end

    def currency_explicit?
      iso = @params[:currency].to_s.upcase
      iso.present? && available_currencies.include?(iso)
    end

    # Distinct currencies the user has ever booked across all owned
    # accounts. Stable across period selection (a chip for an empty
    # currency in the current period is fine — clicking it surfaces the
    # empty state, not surprise behavior).
    def available_currencies
      @available_currencies ||= LedgerEntry
                                  .where(bank_account_id: @user.all_bank_account_ids)
                                  .distinct.pluck(:currency).compact.sort
    end

    # Base relation for the dashboard. Services chain `.spend` / `.income`
    # / `.group(...)` / `.sum` from here. Booked only — pending rows
    # double-count once they settle. Currency-filtered so every sum is
    # in a single, consistent unit.
    #
    # `under_path` (Layer 1 path filter) narrows to a subtree when set —
    # used by drill-down breadcrumb navigation.
    def scope
      base = LedgerEntry.where(bank_account_id: account_ids)
                        .where(currency: currency)
                        .booked.in_range(period.from, period.to)
      under_path.present? ? base.under_path(under_path) : base
    end

    def previous_scope
      prev = period.previous
      base = LedgerEntry.where(bank_account_id: account_ids)
                        .where(currency: currency)
                        .booked.in_range(prev.from, prev.to)
      under_path.present? ? base.under_path(under_path) : base
    end

    # Layer 1 — subtree filter. `?under_path=food.cooking` narrows every
    # widget to that branch. Empty string and nil both mean "no filter".
    def under_path
      @under_path ||= @params[:under_path].to_s.presence
    end

    def root_path
      under_path&.split(".")&.first
    end

    # Depth at which `SpendBreakdown.by_category` should aggregate. With no
    # subtree filter we show top-level domains (1). When drilled into a
    # subtree, we show one level deeper than the subtree root.
    def aggregation_depth
      return 1 if under_path.blank?
      under_path.count(".") + 2
    end

    # Drill-down / chip links propagate the filter. We emit `accounts=none`
    # for the explicit-empty state and `account_ids[]=…` for narrowed
    # state; default state (all accounts) emits neither so a passive
    # click (e.g. period preset) doesn't promote default → explicit.
    # `bucket` is emitted only when the user explicitly picked one — that
    # way changing period (which strips ?bucket) lets the smart default
    # reapply for the new length.
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

    # Most-frequent currency in the user's ledger; PLN fallback when the
    # ledger is empty (fresh user). Single query, cached per-instance.
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
                       Date.current - 6.days
      end
    end

    def to_date
      @to_date ||= if @params[:from].present? && @params[:to].present?
                     parse_date(@params[:to])
      else
                     Date.current
      end
    end

    # Resolve bucket without touching `period` (avoids infinite loop —
    # period itself depends on bucket).
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
