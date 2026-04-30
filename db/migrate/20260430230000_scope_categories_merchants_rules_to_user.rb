class ScopeCategoriesMerchantsRulesToUser < ActiveRecord::Migration[8.1]
  # Multi-tenant scoping for the classification taxonomy. Until now,
  # categories / merchants / merchant_rules were a single shared set —
  # workable for one user, but every form picker and the enricher itself
  # leak across users at the moment a second user signs in.
  #
  # Data plan: only one user exists in any deployed environment at the
  # time of writing (verified before authoring), so backfill assigns
  # everything to User.first. New environments build their own from
  # scratch via UI + LLM enrichment; dev seeds re-seed under the seeded
  # admin user (see db/seeds.rb).
  #
  # Slug uniqueness moves from global to (user_id, slug). The enricher's
  # find_or_initialize_by(slug:) calls in OwnAccountMerchantSyncer and
  # LLM EnrichmentRunner are updated alongside this migration to scope
  # by user, otherwise two users with merchants of the same slug would
  # collide on the new compound index.
  def up
    user_id = User.order(:id).limit(1).pick(:id)
    raise "Cannot backfill — no User exists. Create one first." if user_id.nil?

    add_reference :categories,      :user, foreign_key: true, null: true
    add_reference :merchants,       :user, foreign_key: true, null: true
    add_reference :merchant_rules,  :user, foreign_key: true, null: true

    execute "UPDATE categories       SET user_id = #{user_id} WHERE user_id IS NULL"
    execute "UPDATE merchants        SET user_id = #{user_id} WHERE user_id IS NULL"
    execute "UPDATE merchant_rules   SET user_id = #{user_id} WHERE user_id IS NULL"

    change_column_null :categories,     :user_id, false
    change_column_null :merchants,      :user_id, false
    change_column_null :merchant_rules, :user_id, false

    # Slug uniqueness goes from global to (user_id, slug). Rule slugs
    # don't exist (rules are keyed by merchant_id + pattern); only the
    # two slugged tables get the compound index.
    remove_index :categories, :slug
    remove_index :merchants,  :slug
    add_index :categories, [ :user_id, :slug ], unique: true
    add_index :merchants,  [ :user_id, :slug ], unique: true
  end

  def down
    remove_index :categories, [ :user_id, :slug ]
    remove_index :merchants,  [ :user_id, :slug ]
    add_index :categories, :slug, unique: true
    add_index :merchants,  :slug, unique: true

    remove_reference :merchant_rules, :user, foreign_key: true
    remove_reference :merchants,      :user, foreign_key: true
    remove_reference :categories,     :user, foreign_key: true
  end
end
