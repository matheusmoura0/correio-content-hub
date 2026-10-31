class AddPresentationToSiteArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :site_articles, :display_title, :string
    add_column :site_articles, :image_focus_x, :integer, null: false, default: 50
    add_column :site_articles, :image_focus_y, :integer, null: false, default: 50
    add_column :site_articles, :image_zoom, :decimal, precision: 4, scale: 2, null: false, default: 1.0
  end
end
