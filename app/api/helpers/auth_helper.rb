# frozen_string_literal: true

module Helpers
  module AuthHelper
    extend Grape::API::Helpers

    def current_user
      @current_user ||= authenticate!
    end

    def authenticate!
      result = Auth::PersonalAccessTokenAuthenticator.call(raw_token: bearer_token)
      error!({ message: "Invalid or missing access token." }, 401) unless result.success?
      result.user
    end

    def bearer_token
      header = headers["Authorization"] || request.env["HTTP_AUTHORIZATION"]
      return nil if header.blank?
      header.to_s.sub(/\Abearer\s+/i, "").presence
    end
  end
end
