# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include Pagy::Method

    layout "admin"
    helper Admin::BaseHelper
    before_action :authenticate_admin!
    helper_method :current_admin

    private

    def authenticate_admin!
      @current_admin ||= Data.define(:name, :email, :initials, :role).new(
        name: "Admin User",
        email: "admin@example.com",
        initials: "AU",
        role: "Admin"
      )
    end

    def current_admin
      @current_admin
    end
  end
end
