# frozen_string_literal: true

# Production encryption keys are loaded by ActiveRecord encryption at boot
# from ENV (see config/initializers/active_record_encryption.rb); .env
# supplies them in dev/test. These helpers exist for the handful of model
# specs that read past the encryption layer to confirm on-disk bytes are
# not the plaintext.
module EncryptionHelpers
  def raw_column_value(record, column)
    sql = ActiveRecord::Base.sanitize_sql_for_conditions([
      "SELECT #{record.class.connection.quote_column_name(column)} " \
      "FROM #{record.class.quoted_table_name} WHERE id = ?",
      record.id
    ])
    ActiveRecord::Base.connection.select_value(sql)
  end

  def expect_encrypted_at_rest(record, column, plaintext)
    raw = raw_column_value(record, column)
    expect(raw).not_to be_nil
    expect(raw.to_s).not_to include(plaintext.to_s)
  end
end

RSpec.configure do |config|
  config.include EncryptionHelpers
end
