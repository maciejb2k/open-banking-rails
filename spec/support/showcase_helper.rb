# frozen_string_literal: true

# Helpers for system + smoke specs that share a single Seeders::Showcase
# state across examples in the same describe block. The seeder is expensive
# (hundreds of DB roundtrips through real services); running it once per
# describe — not per example — is the right balance.
#
# System specs run Capybara's server in a separate thread, so transactional
# fixtures don't roll back across threads. Truncation is the only correct
# cleanup strategy. We set it up at the suite level and let each describe
# block call truncate_db / setup_showcase from before(:all) hooks.
module ShowcaseHelper
  def setup_showcase(email: "showcase@example.test", name: "Showcase User", password: "Password123!")
    user = User.create!(email: email, password: password, name: name)
    fake_eb  = Fakes::EnableBankingClient.new
    fake_llm = Fakes::LlmClient.new
    Seeders::Showcase.call(user: user, fake_eb: fake_eb, fake_llm: fake_llm)
    [ user, fake_eb, fake_llm ]
  end

  def truncate_db
    DatabaseCleaner.clean_with(:truncation, except: %w[ar_internal_metadata schema_migrations])
  end
end

RSpec.configure do |config|
  config.include ShowcaseHelper

  config.before(:suite) do
    DatabaseCleaner[:active_record].strategy = :truncation, { except: %w[ar_internal_metadata schema_migrations] }
  end

  # System specs need truncation because Capybara's server runs in another
  # thread; transactional fixtures don't span threads.
  config.before(:each, type: :system) do
    self.class.use_transactional_tests = false if self.class.respond_to?(:use_transactional_tests=)
  end
end
