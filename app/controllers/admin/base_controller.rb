# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include Pagy::Method

    layout "admin"
    helper Admin::BaseHelper
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
  end
end
