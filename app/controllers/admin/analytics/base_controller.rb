# frozen_string_literal: true

module Admin
  module Analytics
    # Shared parent for every analytics screen. Parses the filter once
    # (account_ids[], from, to) and exposes it to views, so the dashboard
    # and drill-downs share the same selection state and query-param
    # contract.
    class BaseController < Admin::BaseController
      before_action :build_filter

      private

      def build_filter
        @filter = ::Analytics::Filter.new(user: current_user, params: params)
      end
    end
  end
end
