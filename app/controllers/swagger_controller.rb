class SwaggerController < ApplicationController
  layout false
  before_action :authenticate_user!

  def index
    version = params.fetch(:version, "v1")
    @spec_url = "/api/#{version}/swagger_doc"
  end
end
