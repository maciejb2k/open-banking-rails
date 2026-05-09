require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module OpenBankingRails
  ADMIN_EDITION = "Personal"
  ADMIN_VERSION = "1.0.1"

  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])

    # `lib/api/` hosts the Grape API. Collapse it so its contents map as if
    # `lib/api/` were itself an autoload root: `lib/api/api.rb` -> `Api`,
    # `lib/api/entities/x.rb` -> `Entities::X`, etc. Without collapse,
    # Zeitwerk would expect `Api::Api`, `Api::Entities::X`.
    Rails.autoloaders.main.collapse("#{root}/lib/api")

    config.generators.system_tests = nil

    config.active_job.queue_adapter = :sidekiq
  end
end
