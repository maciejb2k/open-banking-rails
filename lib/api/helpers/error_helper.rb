# frozen_string_literal: true

module Helpers
  module ErrorHelper
    extend Grape::API::Helpers

    def present_or_fail!(result, with:, status: 200)
      if result.success?
        present_with_status(result.respond_to?(:transaction) ? result.transaction : result, with: with, status: status)
      else
        error!({ message: result.error.presence || "Request failed.", details: Array(result.error_messages) }, 422)
      end
    end

    def present_with_status(object, with:, status: 200)
      self.status status
      present object, with: with
    end
  end
end
