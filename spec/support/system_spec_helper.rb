# frozen_string_literal: true

# System-spec-only configuration. Capybara defaults to rack_test; specs
# requiring JS opt in via metadata. The showcase seeder is expensive, so
# system specs share state across examples through truncation rather than
# per-example transactions.

require "capybara/rspec"

Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]
  end
end
