# frozen_string_literal: true

module Admin
  class PasswordsController < Devise::PasswordsController
    layout "admin_auth"
  end
end
