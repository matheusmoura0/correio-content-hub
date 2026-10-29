interval = [ENV.fetch("EDITORIAL_INTERVAL_SECONDS", "1800").to_i, 60].max
loop do
  begin
    Analytics::UpdateGeoDatabase.call
    Analytics::PruneReaderMetadata.call
  rescue StandardError => error
    Rails.logger.warn("Manutenção de metadados de audiência: #{error.class}")
  end
  begin
    Correio::SyncColumnists.call
  rescue StandardError => error
    Rails.logger.warn("Atualização dos perfis de colunistas: #{error.class}: #{error.message}")
  end
  begin
    Publishing::PrepareCycle.call if ENV.fetch("EDITORIAL_AUTOMATION_ENABLED", "true") == "true"
  rescue StandardError => error
    Rails.logger.error("Ciclo editorial: #{error.class}: #{error.message}")
  end
  sleep interval
end
