# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include Pagy::Method

    layout "admin"
    helper Admin::BaseHelper
    helper Admin::EnrichmentHelper
    before_action :authenticate_user!

    private

    def paginated(scope, default_sort:, includes: nil)
      @q = scope.ransack(params[:q])
      @q.sorts = default_sort if @q.sorts.empty?
      relation = @q.result
      relation = relation.includes(includes) if includes
      pagy(:offset, relation)
    end

    # Open-redirect guard for `?return_to=` - discard anything that doesn't
    # look like an internal admin path.
    def safe_return_to(default:)
      candidate = params[:return_to].to_s
      return default if candidate.blank?
      return default unless candidate.start_with?("/admin/") || candidate.start_with?("/admin?")
      return default if candidate.include?("//")  # block protocol-relative URLs
      candidate
    end
  end
end
