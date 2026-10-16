interval = [ENV.fetch("EDITORIAL_INTERVAL_SECONDS", "1800").to_i, 60].max
loop do
  begin
    Publishing::PrepareCycle.call if ENV.fetch("EDITORIAL_AUTOMATION_ENABLED", "true") == "true"
  rescue StandardError => error
    Rails.logger.error("Ciclo editorial: #{error.class}: #{error.message}")
  end
  sleep interval
end
