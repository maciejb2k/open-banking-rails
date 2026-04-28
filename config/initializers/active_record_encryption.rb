# frozen_string_literal: true

# Wire ActiveRecord encryption keys from ENV in development/test.
# Production should use Rails encrypted credentials.
#
# Note: this initializer runs AFTER the active_record railtie has already
# populated ActiveRecord::Encryption.config from Rails.application.config.
# Setting Rails.application.config.active_record.encryption.* here would be a
# no-op. We must call ActiveRecord::Encryption.configure to mutate the live
# config in place.

if Rails.env.development? || Rails.env.test?
  primary = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
  deterministic = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
  salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

  if [ primary, deterministic, salt ].all?(&:present?)
    ActiveRecord::Encryption.configure(
      primary_key: primary,
      deterministic_key: deterministic,
      key_derivation_salt: salt
    )
  end
end
