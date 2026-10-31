class AddHomepagePlacementToSiteArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :site_articles, :placement, :string, null: false, default: "latest"
    add_column :site_articles, :position, :integer, null: false, default: 0
    add_index :site_articles, [:site_id, :placement, :position]
  end
end
