# frozen_string_literal: true

module Admin
  module Analytics
    # Drill-down into a category subtree. Two flavours of drill:
    #
    #   * by `slug` (route param) — full leaf detail, lands on a merchant
    #     breakdown for that subtree
    #   * by `path` query string — narrows the dashboard scope to the
    #     subtree without leaving the dashboard (handled in Filter)
    #
    # The slug-based route remains for direct linking + bookmarking; the
    # filter-based path is for inline drill-down on the dashboard chart.
    class CategoriesController < BaseController
      def show
        @category = current_user.categories.find_by!(slug: params[:slug])

        # Drilling into a hidden category — or a hidden subtree — would
        # expose what the dashboard hid. Bounce back; user has to remove
        # the category from the hidden list in /admin/settings/preferences.
        if current_user.hides_category?(@category)
          redirect_to admin_analytics_root_path(@filter.to_query_params),
                      alert: "This category is private. Remove it from the hidden list in preferences to open it."
          return
        end

        @rows        = ::Analytics::SpendBreakdown.by_merchant_in_category(@filter.scope, @category, user: current_user)
        @total_cents = @rows.sum(&:amount_cents)

        # Subtree breakdown one level deeper than the category itself —
        # so on `food.cooking` you see supermarket / convenience / bakery /
        # specialty even before drilling further.
        @subtree_rows = if @category.descendants.any?
                          ::Analytics::SpendBreakdown.by_subpath(@filter.scope, under: @category, user: current_user)
        else
                          []
        end

        @custom_breadcrumbs = build_breadcrumbs(@category)
      end

      private

      # Crumb chain: Admin / Analytics / <each ancestor> / <self>.
      # Each ancestor links back to its own drill-down so the user can
      # walk up the tree.
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
