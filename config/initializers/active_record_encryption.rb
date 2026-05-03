# frozen_string_literal: true

# Wire ActiveRecord encryption keys from ENV in every environment.
# Self-hosted deployment is ENV-only - no Rails encrypted credentials in prod.
# Dev/test pull keys from .env via dotenv-rails; production gets them from the
# compose env (the docker-entrypoint generates and persists them on first boot
# if absent, then exports them into the process env before Rails loads).
#
# Note: this initializer runs AFTER the active_record railtie has already
# populated ActiveRecord::Encryption.config from Rails.application.config.
# Setting Rails.application.config.active_record.encryption.* here would be a
# no-op. We must call ActiveRecord::Encryption.configure to mutate the live
# config in place.

primary       = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
deterministic = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
salt          = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

if [ primary, deterministic, salt ].all?(&:present?)
  ActiveRecord::Encryption.configure(
    primary_key: primary,
    deterministic_key: deterministic,
    key_derivation_salt: salt
  )
elsif Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  # SECRET_KEY_BASE_DUMMY is the Rails 8 convention for "we're building the
  # image, no secrets available yet, just precompile assets". Skip the
  # fail-loud check in that case - it only matters at real-server boot.
  raise "ActiveRecord encryption keys missing - set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, " \
        "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY, ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT. " \
        "The docker-entrypoint generates these on first boot when running under compose."
end
