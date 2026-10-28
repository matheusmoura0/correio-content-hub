class AddReaderMetadataToAnalyticsEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :analytics_events, :client_occurred_at, :datetime, precision: 3
    add_column :analytics_events, :page_elapsed_ms, :integer
    add_column :analytics_events, :event_uuid, :uuid
    add_column :analytics_events, :page_view_uuid, :uuid
    add_column :analytics_events, :metadata, :jsonb, null: false, default: {}
    add_index :analytics_events, [:site_id, :event_uuid], unique: true,
      where: "event_uuid IS NOT NULL", name: "index_analytics_events_on_site_event_uuid"
  end
end
