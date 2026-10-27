module Publishing
  class PrepareCycle
    def self.call
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        next unless connection.select_value("SELECT pg_try_advisory_lock(1952999, 3100)")
        begin
          import_errors = 0
          import_warnings = 0
          Feed.where(active: true).find_each do |feed|
            result = Rss::ImportFeed.call(feed)
            import_warnings += result.warnings
          rescue StandardError => error
            import_errors += 1
            Rails.logger.error("Coleta editorial: feed #{feed.id}: #{error.class}: #{error.message}")
          end
          begin
            images = Correio::RecoverImages.call
            import_warnings += images.failed
          rescue StandardError => error
            import_warnings += 1
            Rails.logger.error("Recuperação de fotos: #{error.class}: #{error.message}")
          end
          Site.publication_destinations.find_each do |site|
            PrepareEdition.call(site)
            notices = []
            notices << "#{import_errors} fonte(s) não puderam ser coletadas neste ciclo." if import_errors.positive?
            notices << "#{import_warnings} aviso(s) ao complementar ou importar matérias." if import_warnings.positive?
            warning = notices.any? ? notices.join(" ") : nil
            site.update_columns(editorial_checked_at: Time.current, editorial_cycle_error: warning)
          rescue StandardError => error
            Rails.logger.error("Preparação editorial: site #{site.id}: #{error.class}: #{error.message}")
            site.update_columns(editorial_checked_at: Time.current, editorial_cycle_error: "Não foi possível preparar sugestões neste ciclo.")
          end
        ensure
          connection.execute("SELECT pg_advisory_unlock(1952999, 3100)")
        end
      end
    end
  end
end
