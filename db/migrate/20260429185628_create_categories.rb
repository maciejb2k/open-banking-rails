# frozen_string_literal: true

# Hierarchical, soft-deletable categories for transaction analytics.
#
# Self-referential parent_id keeps the tree to two practical levels (top-level
# group + sub-category) without enforcing depth in the schema. `slug` is the
# stable identifier used by seeds, exports, and rule generators - `name` is a
# display-only field the user can rename freely.
#
# `kind` partitions categories for analytics: only `expense` rows count toward
# "ile wydałem"; `transfer`/`ignored` are excluded from spend totals;
# `savings` separates "moved to savings account" from genuine consumption.
#
# `archived_at` is soft-delete: keeps historical transaction → category links
# valid even after the user retires a category.
class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.references :parent, foreign_key: { to_table: :categories }
      t.string  :name, null: false
      t.string  :slug, null: false
      t.string  :color
      t.string  :icon
      t.string  :kind, null: false, default: "expense"
      t.integer :position, null: false, default: 0
      t.datetime :archived_at

      t.timestamps
    end

    add_index :categories, :slug, unique: true
    add_index :categories, [ :parent_id, :position ]
    add_index :categories, :archived_at
  end
end
