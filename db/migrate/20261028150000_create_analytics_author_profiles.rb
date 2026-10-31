class CreateAnalyticsAuthorProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_author_profiles do |t|
      t.references :site, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.string :source_url, null: false
      t.string :image_url
      t.string :aliases, array: true, default: [], null: false
      t.boolean :individual, default: true, null: false
      t.boolean :active, default: true, null: false
      t.datetime :checked_at
      t.timestamps
    end
    add_index :analytics_author_profiles, [:site_id, :slug], unique: true
    add_column :sites, :analytics_profiles_checked_at, :datetime
  end
end
