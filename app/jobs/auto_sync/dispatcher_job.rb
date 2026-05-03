# frozen_string_literal: true

module AutoSync
  class DispatcherJob < ApplicationJob
    queue_as :default

    def perform
      result = AutoSync::Dispatcher.call
      Rails.logger.info("[AutoSync::DispatcherJob] #{result.to_log_hash}")
    end
  end
end
