class AddPublishingProfileToSites < ActiveRecord::Migration[8.0]
  def change
    add_column :sites, :publication_key, :string
    add_column :sites, :site_type, :string, null: false, default: "editorial"
    add_column :sites, :content_mode, :string, null: false, default: "hub"
    add_column :sites, :external_provider, :string
    add_column :sites, :layout_profile, :string, null: false, default: "standard"
    add_column :sites, :allowed_origins, :text
    add_index :sites, :publication_key, unique: true
  end
end
