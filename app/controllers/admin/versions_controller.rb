# frozen_string_literal: true

module Admin
  class VersionsController < BaseController
    def index
      @pagy, @collection = paginated(PaperTrail::Version, default_sort: "created_at desc")
    end

    def show
      @version = PaperTrail::Version.find(params[:id])
    end
  end
end
