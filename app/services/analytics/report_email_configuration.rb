module Analytics
  module ReportEmailConfiguration
    SENDER = "relatorios@cm.com.br".freeze

    def self.ready?
      %w[SMTP_ADDRESS SMTP_USERNAME SMTP_PASSWORD].all? { |key| ENV[key].present? } &&
        ENV.fetch("SMTP_PORT", "465").match?(/\A(?:465|587|2465|2587)\z/)
    end
  end
end
