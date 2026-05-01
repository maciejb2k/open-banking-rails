# frozen_string_literal: true

module Admin
  module Analytics
    class MerchantsController < BaseController
      def show
        @merchant = current_user.merchants.find_by!(slug: params[:slug])

        # Same logic as analytics/categories: bounce when the merchant's
        # default category is on the user's hidden list.
        if current_user.hides_category?(@merchant.default_category_id)
          redirect_to admin_analytics_root_path(@filter.to_query_params),
                      alert: "Ten sprzedawca jest w ukrytej kategorii. Usuń ją z listy w preferencjach, żeby go otworzyć."
          return
        end

        scope = @filter.scope.spend.where(merchant_id: @merchant.id)
        # Aggregates run on the unpaginated scope so the user sees totals
        # for the full window, not just the current page. Pagy direct
        # (not via the ransack-wrapping `paginated` helper) — sort is
        # fixed and LedgerEntry doesn't allowlist ransack attributes.
        @total_cents = scope.sum(:amount_cents)
        @count       = scope.count
        @pagy, @transactions = pagy(
          :offset,
          scope.includes(:effective_category).order(booking_date: :desc)
        )

        @monthly_trend = ::Analytics::SpendBreakdown.merchant_monthly_trend(
          user: current_user, merchant_id: @merchant.id, currency: @filter.currency
        )

        # Resolve the dominant category for this merchant, used as the
        # middle breadcrumb step. Picks the category most recently
        # associated — falls back to the merchant's default.
        @breadcrumb_category = @transactions.first&.effective_category || @merchant.default_category

        crumbs = [
          { label: "Admin",     path: admin_root_path },
          { label: "Analytics", path: admin_analytics_root_path(@filter.to_query_params) }
        ]
        if @breadcrumb_category&.slug
          crumbs << { label: @breadcrumb_category.name,
                      path:  admin_analytics_category_path(@breadcrumb_category.slug, @filter.to_query_params) }
        end
        crumbs << { label: @merchant.display, sensitive: true }
        @custom_breadcrumbs = crumbs
      end
    end
  end
end
