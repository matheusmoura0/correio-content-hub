module Publishing
  class PrepareCycle
    def self.call
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        next unless connection.select_value("SELECT pg_try_advisory_lock(1952999, 3100)")
        begin
          Feed.where(active: true).find_each do |feed|
            Rss::ImportFeed.call(feed)
          rescue StandardError => error
            Rails.logger.error("Coleta editorial: feed #{feed.id}: #{error.class}: #{error.message}")
          end
          Site.publication_destinations.find_each do |site|
            PrepareEdition.call(site)
          rescue StandardError => error
            Rails.logger.error("Preparação editorial: site #{site.id}: #{error.class}: #{error.message}")
          end
        ensure
          connection.execute("SELECT pg_advisory_unlock(1952999, 3100)")
        end
      end
    end
  end
end
