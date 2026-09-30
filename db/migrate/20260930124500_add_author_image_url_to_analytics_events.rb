class AddAuthorImageUrlToAnalyticsEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :analytics_events, :author_image_url, :text
  end
end
