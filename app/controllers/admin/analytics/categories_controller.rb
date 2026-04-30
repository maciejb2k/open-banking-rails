# frozen_string_literal: true

module Admin
  module Analytics
    class CategoriesController < BaseController
      def show
        @category = Category.find_by!(slug: params[:slug])
        @rows     = ::Analytics::SpendBreakdown.by_merchant_in_category(@filter.scope, @category.id)
        @total_cents = @rows.sum(&:amount_cents)

        @custom_breadcrumbs = [
          { label: "Admin",     path: admin_root_path },
          { label: "Analytics", path: admin_analytics_root_path(@filter.to_query_params) },
          { label: @category.name }
        ]
      end
    end
  end
end
