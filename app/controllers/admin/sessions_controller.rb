# frozen_string_literal: true

module Admin
  class SessionsController < Devise::SessionsController
    layout "admin_auth"
  end
end
