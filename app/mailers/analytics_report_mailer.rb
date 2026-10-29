class AnalyticsReportMailer < ActionMailer::Base
  default from: "Correio da Manhã <relatorios@cm.com.br>"

  def weekly(delivery, pdf)
    start = delivery.period_start
    period = "#{start.strftime('%d/%m/%Y')} a #{(start + 6).strftime('%d/%m/%Y')}"
    attachments["correio-da-manha-#{start}.pdf"] = { mime_type: "application/pdf", content: pdf }
    prefix = delivery.run_key == "weekly" ? "Relatório semanal" : "Prévia do relatório"
    headers["Resend-Idempotency-Key"] = "hub-weekly-#{delivery.id}" if ENV["SMTP_ADDRESS"] == "smtp.resend.com"
    mail(to: delivery.recipient, subject: "#{prefix} de audiência | #{period}",
      message_id: "hub-report-#{delivery.id}@cm.com.br") do |format|
      format.text do
        render plain: "Correio da Manhã\n#{prefix} de audiência\n#{period} (dias completos em UTC)\n\nO PDF em anexo reúne os colunistas com assinatura individual, as notícias mais vistas e os indicadores agregados de público.\n\nDados de localização são aproximados. Metadados de público cobrem somente a coleta recente; grupos pequenos não são exibidos.\n\nEnvio gerenciado pela administração do CM Content Hub. Para deixar de receber, contate a administração da redação. Não responda a este remetente.\n"
      end
    end
  end
end
