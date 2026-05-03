class CreateLlmSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.string :provider, null: false

      # Encrypted at app layer via `encrypts :api_key` (Rails 8 ActiveRecord
      # encryption - same pattern as TppCredential#private_key_pem).
      t.text :api_key, null: false

      t.string :model

      t.datetime :last_tested_at
      t.text :last_test_error

      t.timestamps
    end
  end
end
