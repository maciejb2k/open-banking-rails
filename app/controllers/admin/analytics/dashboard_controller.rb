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
        @net_cents        = totals[:net_cents]
        @prev_spend_cents = prev_totals[:spend_cents]
        @spend_delta_pct  = compute_delta_pct(@spend_cents, @prev_spend_cents)
        # Savings rate is THE personal-finance KPI — what % of income
        # you kept. Nil when no income (would divide by zero); the card
        # then renders "—" instead of a misleading 0%.
        @savings_rate_pct = compute_savings_rate(@income_cents, @spend_cents)

        # Burn rate — period-relative, complements the per-period Spend
        # number ("ile średnio dziennie wydaję w tym oknie").
        @avg_daily_spend_cents = @spend_cents / @filter.period.length_days

        # Cash flow timeline + spend-by-category at full leaf granularity
        # (one bar per distinct path with spend). For the "ile na jedzenie
        # ogólnie" rollup, the user can filter ?under_path=food which
        # narrows the whole dashboard to that subtree.
        @cash_flow      = ::Analytics::CashFlow.series(scope, period: @filter.period)
        @breakdown      = ::Analytics::SpendBreakdown.by_category(
                            scope,
                            user: current_user,
                            previous_scope: prev_scope
                          )
        @top_merchants  = ::Analytics::TopMerchants.call(scope, user: current_user, limit: 8)
        @account_rows   = ::Analytics::AccountBreakdown.call(scope, user: current_user)

        # Layer 2 facet breakdowns — independent of hierarchy.
        @essential_pair = ::Analytics::FacetBreakdown.essential(scope)
        @recurring_pair = ::Analytics::FacetBreakdown.recurring(scope)

        # "Co się zmieniło" — categories with biggest abs swing vs. prev
        # period. Reuses the breakdown rows (already have prev attached),
        # so the panel and the bar chart agree to the cent.
        @top_movers = ::Analytics::TopMovers.from_breakdown(@breakdown, limit: 5)
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
