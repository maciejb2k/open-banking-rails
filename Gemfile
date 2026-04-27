source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false
gem "image_processing", "~> 1.2"

# Admin / pagination / search / audit
gem "pagy", "~> 43.3"
gem "rack-cors"
gem "ransack"
gem "paper_trail"

# Background jobs
gem "sidekiq", "~> 7.0"
gem "connection_pool", "~> 2.4"

# Logging / observability
gem "lograge"
gem "opentelemetry-sdk", "~> 1.10"
gem "opentelemetry-instrumentation-all", "~> 0.91.0"
gem "opentelemetry-instrumentation-logger", "~> 0.3.0"
gem "opentelemetry-exporter-otlp", "~> 0.32.0"
gem "opentelemetry-exporter-otlp-logs", "~> 0.3.0"
gem "opentelemetry-exporter-otlp-metrics", "~> 0.7.0"
gem "opentelemetry-logs-sdk", "~> 0.4.0"
gem "opentelemetry-metrics-sdk", "~> 0.12.0"

group :development, :test do
  gem "dotenv-rails"
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.5"
  gem "shoulda-matchers", "~> 7.0"
  gem "simplecov", require: false
end

group :development do
  gem "web-console"
  gem "annotaterb"
end
