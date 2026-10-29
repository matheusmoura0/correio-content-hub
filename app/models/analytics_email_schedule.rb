class AnalyticsEmailSchedule < ApplicationRecord
  belongs_to :site
  has_many :deliveries, class_name: "AnalyticsEmailDelivery", dependent: :destroy

  before_validation :normalize_recipients
  validates :site_id, uniqueness: true
  validates :hour, inclusion: { in: 0..23 }
  validate :supported_site
  validate :valid_recipients
  validate :ready_to_enable

  def recipients_text
    recipients.join("\n")
  end

  def recipients_text=(text)
    self.recipients = text.to_s.split(/[\s,;]+/)
  end

  def available?
    site&.active? && site.correio_source? && !site.retired_from_hub?
  end

  def due_period(now = Time.current)
    local = now.in_time_zone("America/Sao_Paulo")
    monday = local.to_date.beginning_of_week(:monday)
    return if local < monday.in_time_zone("America/Sao_Paulo") + hour.hours

    monday - 7
  end

  private

  def normalize_recipients
    self.recipients = Array(recipients).map { |email| email.to_s.strip.downcase }.reject(&:blank?).uniq
  end

  def supported_site
    errors.add(:base, "Disponível somente para o Correio da Manhã ativo.") unless available?
  end

  def valid_recipients
    if recipients.size > 30 || recipients.any? { |email| email.bytesize > 254 || !email.match?(/\A[A-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+\z/i) }
      errors.add(:base, "Informe até 30 endereços de e-mail válidos, sem nomes ou cabeçalhos.")
    end
  end

  def ready_to_enable
    return unless enabled?
    errors.add(:base, "Adicione pelo menos um destinatário.") if recipients.empty?
    errors.add(:base, "Configure o serviço de e-mail antes de ativar.") unless Analytics::ReportEmailConfiguration.ready?
  end
end
