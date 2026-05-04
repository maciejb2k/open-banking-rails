class CreatePersonalAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_access_tokens do |t|
      t.references :user, null: false, foreign_key: true

      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :last_four, null: false, limit: 4

      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :personal_access_tokens, :token_digest, unique: true
    add_index :personal_access_tokens, %i[user_id name], unique: true
  end
end
