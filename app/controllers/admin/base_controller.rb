# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include Pagy::Method

    layout "admin"
    helper Admin::BaseHelper
    before_action :authenticate_user!
  end
end
