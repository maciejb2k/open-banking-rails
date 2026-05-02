# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new

  # Load cron entries (currently just AutoSync::DispatcherJob). Server-only:
  # the web/Rails console doesn't need these registered, and loading them
  # there would cause double-registration warnings on reload.
  schedule_file = Rails.root.join("config/schedule.yml")
  if File.exist?(schedule_file)
    Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(schedule_file))
  end
end
