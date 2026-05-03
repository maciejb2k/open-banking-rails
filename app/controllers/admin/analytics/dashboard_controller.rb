# frozen_string_literal: true

module Admin
  module Analytics
    class DashboardController < BaseController
      def index
        scope      = @filter.scope
        prev_scope = @filter.previous_scope
        currency   = @filter.currency

        totals      = ::Analytics::CashFlow.totals(scope)
        prev_totals = ::Analytics::CashFlow.totals(prev_scope)
        @spend_cents      = totals[:spend_cents]
        @income_cents     = totals[:income_cents]
        @net_cents        = totals[:net_cents]
        @prev_spend_cents = prev_totals[:spend_cents]
        @spend_delta_pct  = compute_delta_pct(@spend_cents, @prev_spend_cents)
        @savings_rate_pct = compute_savings_rate(@income_cents, @spend_cents)

        @avg_daily_spend_cents = @spend_cents / @filter.period.length_days

        # Day 1–2 projections explode on a single big lunch (×31), so we
        # hold run-rate back until day 3 - avg-daily-spend stays as a
        # sensible placeholder.
        if @filter.month_to_date?
          days_elapsed  = @filter.period.length_days
          days_in_month = Date.current.end_of_month.day
          if days_elapsed >= 3
            @run_rate_cents = (@spend_cents.to_f * days_in_month / days_elapsed).round
          end
          if (prev_month_scope = @filter.previous_full_month_scope)
            @prev_full_month_spend_cents = ::Analytics::CashFlow.totals(prev_month_scope)[:spend_cents]
          end
        end

        @cash_flow      = ::Analytics::CashFlow.series(scope, period: @filter.period, currency: currency)
        @breakdown      = ::Analytics::SpendBreakdown.by_category(
                            scope,
                            user: current_user,
                            currency: currency,
                            previous_scope: prev_scope
                          )
        @top_merchants  = ::Analytics::TopMerchants.call(scope, user: current_user, currency: currency, limit: 8)
        @account_rows   = ::Analytics::AccountBreakdown.call(scope, user: current_user, currency: currency)

        @domain_breakdown = ::Analytics::SpendBreakdown.by_category(
                              scope,
                              user:           current_user,
                              currency:       currency,
                              depth:          @filter.aggregation_depth,
                              previous_scope: prev_scope
                            )

        @drill_category = current_user.categories.find_by(path: @filter.under_path) if @filter.under_path.present?

        @essential_pair = ::Analytics::FacetBreakdown.essential(scope, currency: currency)
        @recurring_pair = ::Analytics::FacetBreakdown.recurring(scope, currency: currency)

        @top_movers = ::Analytics::TopMovers.from_breakdown(@breakdown, limit: 5)

        @top_transactions = scope.spend
                                 .includes(:merchant, :bank_account, :effective_category)
                                 .order(amount_cents: :desc)
                                 .limit(5)

        # Unmatched debits are invisible to `.spend` (which requires
        # `categories.kind = 'expense'`), so they silently distort every
        # total on the dashboard. Surface them as a persistent banner.
        unmatched_scope          = scope.debits.where(effective_category_id: nil)
        @unmatched_count         = unmatched_scope.count
        @unmatched_amount_cents  = unmatched_scope.sum(:amount_cents)
        # Denominator is spend + unmatched so the % reads as "of the
        # totals' true value, this much is missing".
        denom = @spend_cents + @unmatched_amount_cents
        @unmatched_share_pct = denom.positive? ?
                               (@unmatched_amount_cents.to_f / denom * 100).round : 0
      end

      private

      def compute_delta_pct(current, prev)
        return nil if prev.zero?
        (((current - prev).to_f / prev) * 100).round
      end

      def compute_savings_rate(income_cents, spend_cents)
        return nil if income_cents.zero?
        (((income_cents - spend_cents).to_f / income_cents) * 100).round
      end
    end
  end
end
