class CreateAnalyticsEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_events do |t|
      t.references :site, null: false, foreign_key: true
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.string :path, null: false
      t.string :page_title
      t.string :content_key
      t.string :content_category
      t.string :content_author
      t.string :target_url
      t.string :target_text
      t.string :referrer
      t.string :session_hash, null: false
      t.string :visitor_hash, null: false
      t.string :device_type, null: false
      t.string :country_code
      t.integer :value, null: false, default: 0
      t.timestamps
    end

    add_index :analytics_events, [:site_id, :occurred_at]
    add_index :analytics_events, [:site_id, :event_type, :occurred_at], name: "index_analytics_events_on_site_type_time"
    add_index :analytics_events, [:site_id, :path, :occurred_at]
    add_index :analytics_events, [:site_id, :content_key, :occurred_at], name: "index_analytics_events_on_site_content_time"
    add_index :analytics_events, [:site_id, :visitor_hash, :occurred_at], name: "index_analytics_events_on_site_visitor_time"
  end
end
