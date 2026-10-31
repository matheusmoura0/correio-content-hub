module Analytics
  class PruneReaderMetadata
    def self.call
      # Keep historical audience totals; remove only new reader enrichment after 90 days.
      AnalyticsEvent.where("occurred_at < ? AND metadata <> '{}'::jsonb", 90.days.ago).in_batches(of: 2_000) do |batch|
        batch.update_all(metadata: {}, client_occurred_at: nil, page_elapsed_ms: nil,
          event_uuid: nil, page_view_uuid: nil, country_code: nil)
      end
    end
  end
end
