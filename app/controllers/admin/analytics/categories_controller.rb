# frozen_string_literal: true

module Admin
  module Analytics
    class CategoriesController < BaseController
      def show
        @category = current_user.categories.find_by!(slug: params[:slug])

        # Drilling into a hidden category would expose what the dashboard hid.
        if current_user.hides_category?(@category)
          redirect_to admin_analytics_root_path(@filter.to_query_params),
                      alert: "This category is private. Remove it from the hidden list in preferences to open it."
          return
        end

        @rows        = ::Analytics::SpendBreakdown.by_merchant_in_category(@filter.scope, @category, user: current_user, currency: @filter.currency)
        @total_cents = @rows.sum(&:amount_cents)

        @subtree_rows = if @category.descendants.any?
                          ::Analytics::SpendBreakdown.by_subpath(@filter.scope, under: @category, user: current_user, currency: @filter.currency)
        else
                          []
        end

        @custom_breadcrumbs = build_breadcrumbs(@category)
      end

      private

      def build_breadcrumbs(category)
        chain = [
          { label: "Admin",     path: admin_root_path },
          { label: "Analytics", path: admin_analytics_root_path(@filter.to_query_params) }
        ]
        category.ancestors.order(Arel.sql("nlevel(path)")).each do |a|
          next if current_user.hides_category?(a)
          chain << { label: a.name, path: admin_analytics_category_path(a.slug, @filter.to_query_params) }
        end
        chain << { label: category.name }
        chain
      end
    end
  end
end
