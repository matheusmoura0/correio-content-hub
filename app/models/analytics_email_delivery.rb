class AnalyticsEmailDelivery < ApplicationRecord
  belongs_to :analytics_email_schedule
  STATUSES = {
    "pending" => "Na fila", "sending" => "Em envio / conferir provedor", "accepted" => "Aceito pelo provedor",
    "retry" => "Nova tentativa programada", "failed" => "Falhou", "uncertain" => "Conferir no provedor", "cancelled" => "Cancelado"
  }.freeze
  validates :status, inclusion: { in: STATUSES.keys }
  validates :period_start, :recipient, :run_key, presence: true
  validate :valid_period

  def report_end
    period_end || period_start + 6
  end

  def kind
    return "weekly" if run_key == "weekly"
    run_key.to_s.start_with?("manual-") ? "manual" : "preview"
  end

  def kind_label
    { "weekly" => "Semanal", "manual" => "Manual", "preview" => "Prévia" }.fetch(kind)
  end

  def eligible?(now)
    status == "pending" || (status == "retry" && attempts < 3 && attempted_at <= now - 30.minutes)
  end

  private

  def valid_period
    return unless period_start && period_end
    errors.add(:period_end, "deve estar entre o início e até 89 dias depois") unless (period_start..period_start + 89).cover?(period_end)
  end
end
