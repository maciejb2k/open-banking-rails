# frozen_string_literal: true

module Admin
  module Analytics
    class DashboardController < BaseController
      def index
        scope      = @filter.scope
        prev_scope = @filter.previous_scope

        # Stat-card aggregates. Two single-query passes (current totals,
        # previous totals); the previous pass powers the spend Δ%.
        totals      = ::Analytics::CashFlow.totals(scope)
        prev_totals = ::Analytics::CashFlow.totals(prev_scope)
        @spend_cents      = totals[:spend_cents]
        @income_cents     = totals[:income_cents]
        @prev_spend_cents = prev_totals[:spend_cents]
        @spend_delta_pct  = compute_delta_pct(@spend_cents, @prev_spend_cents)

        # Burn rate — period-relative, complements the per-period Spend
        # number ("ile średnio dziennie wydaję w tym oknie").
        @avg_daily_spend_cents = @spend_cents / @filter.period.length_days

        # Cash flow timeline + spend-by-category (with prev overlay).
        @cash_flow      = ::Analytics::CashFlow.daily_series(scope, period: @filter.period)
        @breakdown      = ::Analytics::SpendBreakdown.by_category(scope, user: current_user, previous_scope: prev_scope)
        @top_merchants  = ::Analytics::TopMerchants.call(scope, user: current_user, limit: 8)
        @account_rows   = ::Analytics::AccountBreakdown.call(scope, user: current_user)

        # Single biggest line item — useful at-a-glance (who you fed most).
        @top_merchant = @top_merchants.first
      end

      private

      def compute_delta_pct(current, prev)
        return nil if prev.zero?
        (((current - prev).to_f / prev) * 100).round
      end
    end
  end
end
