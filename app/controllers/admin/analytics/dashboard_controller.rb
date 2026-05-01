# frozen_string_literal: true

module Admin
  module Analytics
    class DashboardController < BaseController
      def index
        scope      = @filter.scope
        prev_scope = @filter.previous_scope
        currency   = @filter.currency

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

        # Run-rate — projected EOM spend at the current pace. Only
        # meaningful for MTD (the question is "how am I doing this
        # month"); for arbitrary windows the dashboard falls back to
        # avg-daily-spend.
        # Day 1–2 projections explode on a single big lunch (×31), so
        # we hold the run-rate back until day 3 — avg-daily-spend keeps
        # showing as a sensible placeholder.
        if @filter.month_to_date?
          days_elapsed  = @filter.period.length_days
          days_in_month = Date.current.end_of_month.day
          if days_elapsed >= 3
            @run_rate_cents = (@spend_cents.to_f * days_in_month / days_elapsed).round
          end
          # Previous full calendar month — yardstick for "is this month
          # tracking better/worse than last?". Single totals query.
          if (prev_month_scope = @filter.previous_full_month_scope)
            @prev_full_month_spend_cents = ::Analytics::CashFlow.totals(prev_month_scope)[:spend_cents]
          end
        end

        # Cash flow timeline + spend-by-category at full leaf granularity
        # (one bar per distinct path with spend). For the "ile na jedzenie
        # ogólnie" rollup, the user can filter ?under_path=food which
        # narrows the whole dashboard to that subtree.
        @cash_flow      = ::Analytics::CashFlow.series(scope, period: @filter.period, currency: currency)
        @breakdown      = ::Analytics::SpendBreakdown.by_category(
                            scope,
                            user: current_user,
                            currency: currency,
                            previous_scope: prev_scope
                          )
        @top_merchants  = ::Analytics::TopMerchants.call(scope, user: current_user, currency: currency, limit: 8)
        @account_rows   = ::Analytics::AccountBreakdown.call(scope, user: current_user, currency: currency)

        # Layer-1 rollup. Depth follows current drill — at root that's 1
        # (food / mobility / home / …), one level under "food" it becomes 2
        # (food.cooking / food.eating_out), and so on. Empty when the user
        # has drilled to a leaf with no descendants — the card just hides.
        @domain_breakdown = ::Analytics::SpendBreakdown.by_category(
                              scope,
                              user:           current_user,
                              currency:       currency,
                              depth:          @filter.aggregation_depth,
                              previous_scope: prev_scope
                            )

        # Active drill — used by the "× Clear" affordance below the page
        # header and to title the rollup card ("Spend in Food").
        @drill_category = current_user.categories.find_by(path: @filter.under_path) if @filter.under_path.present?

        # Layer 2 facet breakdowns — independent of hierarchy.
        @essential_pair = ::Analytics::FacetBreakdown.essential(scope, currency: currency)
        @recurring_pair = ::Analytics::FacetBreakdown.recurring(scope, currency: currency)

        # "Co się zmieniło" — categories with biggest abs swing vs. prev
        # period. Reuses the breakdown rows (already have prev attached),
        # so the panel and the bar chart agree to the cent.
        @top_movers = ::Analytics::TopMovers.from_breakdown(@breakdown, limit: 5)

        @top_transactions = scope.spend
                                 .includes(:merchant, :bank_account, :effective_category)
                                 .order(amount_cents: :desc)
                                 .limit(5)

        # Unmatched debits — debits with no effective_category in the
        # current view. They're invisible to `.spend` (which requires
        # `categories.kind = 'expense'`), so they silently distort every
        # total on the dashboard. We surface them as a persistent banner
        # so the user sees how much of the picture is missing without
        # having to drill into a queue.
        # Two queries (count + sum) — could be one with a single `pluck`
        # and ruby-side reduce, but at personal-app scale not worth the
        # cleverness.
        unmatched_scope          = scope.debits.where(effective_category_id: nil)
        @unmatched_count         = unmatched_scope.count
        @unmatched_amount_cents  = unmatched_scope.sum(:amount_cents)
        # Share of "spend that should have been there" — denominator is
        # spend + unmatched so the % reads as "of the totals' true
        # value, this much is missing".
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
