class CreateTppCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :tpp_credentials do |t|
      t.references :user, null: false, foreign_key: true

      t.string :name, null: false
      t.string :provider, null: false, default: "enable_banking"
      t.string :environment
      t.string :status, null: false, default: "pending"
      t.boolean :primary, null: false, default: false

      # Encrypted at app layer via `encrypts :col` (Rails 8 ActiveRecord encryption)
      t.text :application_id
      t.text :private_key_pem

      # Cert is public material — keep clear so we can introspect without decrypt
      t.text :public_cert_pem
      t.datetime :cert_expires_at

      t.string :redirect_url

      t.datetime :last_verified_at
      t.text :last_verification_error
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :tpp_credentials, :status
    add_index :tpp_credentials, :provider
    add_index :tpp_credentials, :user_id, unique: true,
                                          where: '"primary" = true',
                                          name: "index_one_primary_tpp_credential_per_user"
  end
end
