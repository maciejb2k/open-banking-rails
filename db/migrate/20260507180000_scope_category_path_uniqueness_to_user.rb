# frozen_string_literal: true

class ScopeCategoryPathUniquenessToUser < ActiveRecord::Migration[8.0]
  def up
    remove_index :categories, name: "index_categories_on_path_unique"
    add_index :categories, [ :user_id, :path ], unique: true, name: "index_categories_on_user_id_and_path"
  end

  def down
    remove_index :categories, name: "index_categories_on_user_id_and_path"
    add_index :categories, :path, unique: true, name: "index_categories_on_path_unique"
  end
end
