class AddSearchModeToTopics < ActiveRecord::Migration[8.0]
  def change
    add_column :topics, :search_mode, :string, null: false, default: "web"
    add_index :topics, :search_mode
  end
end
