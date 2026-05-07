require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)

require "capybara/rails"
require "capybara/rspec"

require "sidekiq/testing"
Sidekiq::Testing.fake!

require "rspec-sidekiq"
require "database_cleaner/active_record"

PaperTrail.enabled = false

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [
    Rails.root.join("spec/fixtures")
  ]

  config.use_transactional_fixtures = true

  config.infer_spec_type_from_file_location!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers

  config.include SignInHelpers, type: :request
  config.include SignInHelpers, type: :system
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :system
  config.include SidekiqHelpers
  config.include FakesHelpers
  config.include TimeHelpers

  config.example_status_persistence_file_path = ".rspec_status"

  config.before(:each) do
    Sidekiq::Worker.clear_all
  end

  config.before(:each, :sidekiq_inline) do
    Sidekiq::Testing.inline!
  end

  config.after(:each, :sidekiq_inline) do
    Sidekiq::Testing.fake!
  end

  config.before(:each, :papertrail) do
    PaperTrail.enabled = true
  end

  config.after(:each, :papertrail) do
    PaperTrail.enabled = false
  end

  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.filter_rails_from_backtrace!
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
