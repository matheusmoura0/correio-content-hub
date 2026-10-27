class TrackRssEnrichmentWarnings < ActiveRecord::Migration[8.0]
  def change
    add_column :articles, :source_enrichment_attempted_at, :datetime
    add_column :feeds, :last_import_warning_count, :integer, null: false, default: 0
  end
end
