# frozen_string_literal: true

module Admin
  module Analytics
    class CategoriesController < BaseController
      def show
        @category = current_user.categories.find_by!(slug: params[:slug])

        # Drilling into a hidden category would expose everything the
        # dashboard hid. Bounce back; user has to remove the category
        # from the hidden list in /admin/settings/preferences to open it.
        if current_user.hides_category?(@category)
          redirect_to admin_analytics_root_path(@filter.to_query_params),
                      alert: "Ta kategoria jest ukryta. Usuń ją z listy w preferencjach, żeby ją otworzyć."
          return
        end

        @rows     = ::Analytics::SpendBreakdown.by_merchant_in_category(@filter.scope, @category.id, user: current_user)
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
