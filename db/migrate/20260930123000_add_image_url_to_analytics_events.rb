class AddImageUrlToAnalyticsEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :analytics_events, :image_url, :text
  end
end
