# frozen_string_literal: true

module AutoSync
  # Wakes once per minute via sidekiq-cron (config/schedule.yml). Pure
  # delegate to AutoSync::Dispatcher — keeps the job thin so all dispatch
  # logic stays testable without Sidekiq.
  class DispatcherJob < ApplicationJob
    queue_as :default

    def perform
      result = AutoSync::Dispatcher.call
      Rails.logger.info("[AutoSync::DispatcherJob] #{result.to_log_hash}")
    end
  end
end
