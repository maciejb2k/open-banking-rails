class AddRevealHiddenCategoriesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :reveal_hidden_categories, :boolean, default: false, null: false
  end
end
