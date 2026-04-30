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
      @period ||= if @params[:from].present? && @params[:to].present?
                    Period.new(from: parse_date(@params[:from]), to: parse_date(@params[:to]))
      else
                    Period.last_n_days(7)
      end
    end

    # Base relation for the dashboard. Services chain `.spend` / `.income`
    # / `.group(...)` / `.sum` from here. Booked only — pending rows
    # double-count once they settle.
    def scope
      LedgerEntry.where(bank_account_id: account_ids).booked.in_range(period.from, period.to)
    end

    def previous_scope
      prev = period.previous
      LedgerEntry.where(bank_account_id: account_ids).booked.in_range(prev.from, prev.to)
    end

    # Drill-down / chip links propagate the filter. We emit `accounts=none`
    # for the explicit-empty state and `account_ids[]=…` for narrowed
    # state; default state (all accounts) emits neither so a passive
    # click (e.g. period preset) doesn't promote default → explicit.
    def to_query_params
      params = { from: period.from.iso8601, to: period.to.iso8601 }
      if none?
        params[:accounts] = "none"
      elsif explicit_account_ids.any?
        params[:account_ids] = explicit_account_ids
      end
      params
    end

    private

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      Date.current
    end
  end
end
