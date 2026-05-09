source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "propshaft", "~> 1.3"
gem "pg", "~> 1.6"
gem "puma", "~> 8.0"
gem "importmap-rails", "~> 2.2"
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails", "~> 1.3"
gem "tailwindcss-rails", "~> 4.4"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", "~> 1.24", require: false
gem "image_processing", "~> 1.14"
gem "redis", "~> 5.4"

gem "devise", "~> 5.0"

gem "faraday", "~> 2.14"
gem "jwt", "~> 2.10"

gem "money-rails", "~> 3.0"

gem "pagy", "~> 43.5"
gem "rack-cors", "~> 3.0"
gem "ransack", "~> 4.4"
gem "paper_trail", "~> 17.0"

gem "grape", "~> 3.2"
gem "grape-entity", "~> 1.0"
gem "grape-swagger", "~> 2.1"
gem "grape-swagger-entity", "~> 0.7"

gem "mcp", "~> 0.15"

gem "gutentag", "~> 3.0"

gem "scenic", "~> 1.9"

gem "sidekiq", "~> 7.3"
gem "sidekiq-cron", "~> 2.4"
gem "connection_pool", "~> 2.5"

gem "ruby_llm", "~> 1.15"

gem "lograge", "~> 0.14"
gem "opentelemetry-sdk", "~> 1.11"
gem "opentelemetry-instrumentation-all", "~> 0.91.0"
gem "opentelemetry-instrumentation-logger", "~> 0.3.0"
gem "opentelemetry-exporter-otlp", "~> 0.32.0"
gem "opentelemetry-exporter-otlp-logs", "~> 0.3.0"
gem "opentelemetry-exporter-otlp-metrics", "~> 0.7.0"
gem "opentelemetry-logs-sdk", "~> 0.4.0"
gem "opentelemetry-metrics-sdk", "~> 0.12.0"

group :development, :test do
  gem "dotenv-rails", "~> 3.2"
  gem "debug", "~> 1.11", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", "~> 0.9", require: false
  gem "brakeman", "~> 8.0", require: false
  gem "rubocop-rails-omakase", "~> 1.1", require: false
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.5"
  gem "shoulda-matchers", "~> 7.0"
  gem "simplecov", "~> 0.22", require: false
  gem "webmock", "~> 3.26"
  gem "capybara", "~> 3.40"
  gem "rspec-sidekiq", "~> 5.3"
  gem "faker", "~> 3.8"
end

group :test do
  gem "database_cleaner-active_record", "~> 2.2"
end

group :development do
  gem "web-console", "~> 4.3"
  gem "annotaterb", "~> 4.22"
  gem "bullet", "~> 8.1"
end
