# frozen_string_literal: true

# Foundation for the three-layer category model:
#
#   Layer 1 - hierarchy: replaces `categories.parent_id` (capped at depth 2)
#             with `categories.path` (PG ltree, unbounded depth, slug-based
#             segments - `food.cooking.supermarket`). Native ltree, no gem
#             on top - slug paths read better than the id-paths the
#             ancestry gem would produce.
#
#   Layer 2 - facets: `categories.essential` (needs vs wants) +
#             `transaction_enrichments.recurring` / `recurrence_interval`
#             (cyclical charges as a property, not a category).
#
#   Layer 3 - tags: gutentag tables (Tag + Tagging join), polymorphic
#             but only attached to TransactionEnrichment in this app.
#
# Local dev: drops `parent_id` straight away. Production cutover (when it
# happens) reseeds the tree from scratch - every existing category gets
# repointed to a leaf in the new taxonomy via db/seeds/categories.rb,
# then `parent_id` goes. There is no in-place ancestry backfill because
# the new taxonomy's slugs don't 1:1 match the old ones.
class LayeredCategoriesFoundation < ActiveRecord::Migration[8.1]
  def up
    enable_extension "ltree"

    # Gutentag tables - all three migrations from the gem, collapsed.
    create_table :gutentag_taggings do |t|
      t.bigint :tag_id,         null: false
      t.bigint :taggable_id,    null: false
      t.string :taggable_type,  null: false
      t.timestamps null: false
    end
    add_index :gutentag_taggings, :tag_id
    add_index :gutentag_taggings, %i[taggable_type taggable_id]
    add_index :gutentag_taggings, %i[taggable_type taggable_id tag_id],
              unique: true, name: "unique_taggings"

    create_table :gutentag_tags do |t|
      t.string  :name,           null: false
      t.integer :taggings_count, null: false, default: 0
      t.timestamps null: false
    end
    add_index :gutentag_tags, :name, unique: true
    add_index :gutentag_tags, :taggings_count

    # Categories: parent_id was already dropped by an out-of-band cleanup
    # before this migration; if still present (fresh checkout), drop it.
    if column_exists?(:categories, :parent_id)
      remove_foreign_key :categories, column: :parent_id
      remove_index :categories, name: "index_categories_on_parent_id_and_position", if_exists: true
      remove_index :categories, name: "index_categories_on_parent_id", if_exists: true
      remove_column :categories, :parent_id
    end

    # Full path including the leaf - `food.cooking.supermarket`. Slug
    # segments separated by dots, ltree-native. GiST index supports
    # subtree containment (`<@`), ancestor (`@>`), and lquery patterns
    # (`~ 'food.*{1}'` for direct children only).
    add_column :categories, :path, :ltree
    add_index  :categories, :path, using: :gist
    add_index  :categories, :path, unique: true, name: "index_categories_on_path_unique"

    # `essential` is the needs-vs-wants axis. Default false so a
    # newly-imported category isn't accidentally counted as essential
    # before the user reviews it.
    add_column :categories, :essential, :boolean, null: false, default: false

    # TransactionEnrichment: recurring is a property of the charge,
    # not the category. Detected by Recurrence::Detector, overridable
    # by user. `recurrence_interval` is enum-shaped (weekly/monthly/
    # yearly) but stored as text so a future rrule string ("every 3
    # months on the 15th") doesn't require another migration.
    add_column :transaction_enrichments, :recurring, :boolean, null: false, default: false
    add_column :transaction_enrichments, :recurrence_interval, :string
    add_index  :transaction_enrichments, :recurring, where: "recurring = true"
  end

  def down
    remove_index  :transaction_enrichments, name: "index_transaction_enrichments_on_recurring"
    remove_column :transaction_enrichments, :recurrence_interval
    remove_column :transaction_enrichments, :recurring

    remove_index  :categories, name: "index_categories_on_path_unique"
    remove_index  :categories, name: "index_categories_on_path"
    remove_column :categories, :essential
    remove_column :categories, :path

    add_column :categories, :parent_id, :bigint
    add_index  :categories, :parent_id
    add_index  :categories, %i[parent_id position]
    add_foreign_key :categories, :categories, column: :parent_id

    drop_table :gutentag_tags
    drop_table :gutentag_taggings

    disable_extension "ltree"
  end
end
