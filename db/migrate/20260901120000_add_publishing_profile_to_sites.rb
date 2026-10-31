class AddPublishingProfileToSites < ActiveRecord::Migration[8.0]
  def up
    add_column :sites, :publication_key, :string
    add_column :sites, :site_type, :string, null: false, default: "editorial"
    add_column :sites, :content_mode, :string, null: false, default: "hub"
    add_column :sites, :external_provider, :string
    add_column :sites, :layout_profile, :string, null: false, default: "standard"
    add_column :sites, :allowed_origins, :text

    execute <<~SQL
      UPDATE sites
      SET publication_key = regexp_replace(lower(domain), '[^a-z0-9]+', '-', 'g')
      WHERE publication_key IS NULL
    SQL

    change_column_null :sites, :publication_key, false
    add_index :sites, :publication_key, unique: true
  end

  def down
    remove_index :sites, :publication_key
    remove_columns :sites, :publication_key, :site_type, :content_mode,
      :external_provider, :layout_profile, :allowed_origins
  end
end
