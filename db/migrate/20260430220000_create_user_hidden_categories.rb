class CreateUserHiddenCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :user_hidden_categories do |t|
      t.references :user,     null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.timestamps
      t.index [ :user_id, :category_id ], unique: true
    end
  end
end
