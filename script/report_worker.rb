loop do
  begin
    Analytics::SendWeeklyReports.call
  rescue StandardError => error
    Rails.logger.error("Report email worker: #{error.class}")
  end
  sleep 5
end
