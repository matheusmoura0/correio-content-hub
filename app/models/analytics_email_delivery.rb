class AnalyticsEmailDelivery < ApplicationRecord
  belongs_to :analytics_email_schedule
  STATUSES = {
    "pending" => "Na fila", "sending" => "Em envio / conferir provedor", "accepted" => "Aceito pelo provedor",
    "retry" => "Nova tentativa programada", "failed" => "Falhou", "uncertain" => "Conferir no provedor", "cancelled" => "Cancelado"
  }.freeze
  validates :status, inclusion: { in: STATUSES.keys }
  validates :period_start, :recipient, :run_key, presence: true

  def eligible?(now)
    status == "pending" || (status == "retry" && attempts < 3 && attempted_at <= now - 30.minutes)
  end
end
