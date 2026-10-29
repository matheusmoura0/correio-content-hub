require "net/smtp"

module Analytics
  class SendWeeklyReports
    def self.call(now: Time.current)
      new(now).call
    end

    def initialize(now)
      @now = now
    end

    def call
      return unless ReportEmailConfiguration.ready?

      AnalyticsEmailSchedule.find_each do |schedule|
        schedule.with_lock do
          next unless schedule.available?
          period = schedule.due_period(@now)
          if schedule.enabled? && period
            schedule.recipients.each do |recipient|
              schedule.deliveries.create_or_find_by!(period_start: period, recipient: recipient, run_key: "weekly")
            end
          end
        end
        pdfs = {}
        schedule.deliveries.where(status: %w[pending retry]).order(:id).find_each do |delivery|
          process(schedule, delivery, pdfs)
        end
      rescue StandardError => error
        Rails.logger.error("Weekly analytics report unavailable: #{error.class}")
      end
    end

    private

    def process(schedule, delivery, pdfs)
      # Persist the claim before SMTP: a crash or ambiguous network result must not cause a duplicate send.
      claimed = delivery.with_lock do
        next false unless delivery.eligible?(@now)
        schedule.reload
        allowed = schedule.available? && (delivery.run_key != "weekly" ||
          (schedule.enabled? && schedule.recipients.include?(delivery.recipient) && delivery.period_start == schedule.due_period(@now)))
        unless allowed
          delivery.update!(status: "cancelled")
          next false
        end
        delivery.update!(status: "sending", attempts: delivery.attempts + 1, attempted_at: @now, error_code: nil)
        true
      end
      return unless claimed

      transport_started = false
      pdf = pdfs[delivery.period_start] ||= begin
        from = delivery.period_start.to_time(:utc)
        report = EditorialReport.new(site: schedule.site, from: from, to: from + 7.days)
        PdfReport.new(report).call
      end
      transport_started = true
      AnalyticsReportMailer.weekly(delivery, pdf).deliver_now
      delivery.update!(status: "accepted", accepted_at: Time.current)
    rescue Net::SMTPServerBusy => error
      delivery.update!(status: delivery.attempts < 3 ? "retry" : "failed", error_code: error.class.name)
    rescue Net::SMTPFatalError, Net::SMTPAuthenticationError, Net::SMTPSyntaxError => error
      delivery.update!(status: "failed", error_code: error.class.name)
    rescue StandardError => error
      delivery.update!(status: transport_started ? "uncertain" : (delivery.attempts < 3 ? "retry" : "failed"), error_code: error.class.name)
    end
  end
end
