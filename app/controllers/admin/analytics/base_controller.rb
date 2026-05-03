# frozen_string_literal: true

module Admin
  module Analytics
    class BaseController < Admin::BaseController
      before_action :build_filter

      private

      def build_filter
        @filter = ::Analytics::Filter.new(user: current_user, params: params)
      end
    end
  end
end
