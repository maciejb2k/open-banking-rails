# frozen_string_literal: true

module Admin
  class VersionsController < BaseController
    def index
      @q = PaperTrail::Version.ransack(params[:q])
      @q.sorts = "created_at desc" if @q.sorts.empty?
      @pagy, @collection = pagy(:offset, @q.result)
    end

    def show
      @version = PaperTrail::Version.find(params[:id])
    end

    private

  end
end
