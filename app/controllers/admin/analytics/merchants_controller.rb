# frozen_string_literal: true

module Admin
  module Analytics
    class MerchantsController < BaseController
      def show
        @merchant = Merchant.find_by!(slug: params[:slug])

        scope = @filter.scope.spend.where(merchant_id: @merchant.id)
        @transactions = scope.includes(:effective_category)
                             .order(booking_date: :desc)
                             .limit(200)
        @total_cents = scope.sum(:amount_cents)
        @count       = scope.count

        @monthly_trend = ::Analytics::SpendBreakdown.merchant_monthly_trend(
          user: current_user, merchant_id: @merchant.id
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
