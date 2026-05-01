# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include Pagy::Method

    layout "admin"
    helper Admin::BaseHelper
    helper Admin::EnrichmentHelper
    before_action :authenticate_user!

    private

    # Standard ransack + pagy idiom used across index actions.
    # Returns [pagy, collection]; the caller is responsible for
    # exposing them via instance variables and providing `@q`
    # itself when the view needs the search form.
    def paginated(scope, default_sort:, includes: nil)
      @q = scope.ransack(params[:q])
      @q.sorts = default_sort if @q.sorts.empty?
      relation = @q.result
      relation = relation.includes(includes) if includes
      pagy(:offset, relation)
    end

    # Resolves a `?return_to=` query / hidden-field value to a safe
    # in-app path or falls back to `default`. Guards against open-redirect
    # — anything that doesn't look like an internal admin path is
    # discarded silently.
    #
    # Use after a state-changing action (update / destroy / approve)
    # when the user might have arrived from a different page than the
    # one the action's "logical" default points to. The launching view
    # threads a `return_to:` URL through the link / form; this helper
    # is the trust boundary on the way back.
    def safe_return_to(default:)
      candidate = params[:return_to].to_s
      return default if candidate.blank?
      return default unless candidate.start_with?("/admin/") || candidate.start_with?("/admin?")
      return default if candidate.include?("//")  # block protocol-relative URLs
      candidate
    end
  end
end
