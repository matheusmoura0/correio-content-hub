class AddImageRightsMetadataToArticles < ActiveRecord::Migration[8.0]
  def up
    add_column :articles, :original_image_url, :string
    add_column :articles, :image_source_url, :string
    add_column :articles, :image_author, :string
    add_column :articles, :image_license, :string
    add_column :articles, :image_license_url, :string
    add_column :articles, :image_rights_confirmed_at, :datetime
    add_reference :articles, :image_rights_confirmed_by, foreign_key: { to_table: :users }, index: true

    execute <<~SQL
      UPDATE articles
      SET original_image_url = image_url
      WHERE image_url IS NOT NULL AND image_url <> ''
    SQL
  end

  def down
    remove_reference :articles, :image_rights_confirmed_by, foreign_key: { to_table: :users }
    remove_column :articles, :image_rights_confirmed_at
    remove_column :articles, :image_license_url
    remove_column :articles, :image_license
    remove_column :articles, :image_author
    remove_column :articles, :image_source_url
    remove_column :articles, :original_image_url
  end
end
