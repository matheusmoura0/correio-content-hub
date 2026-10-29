class AnalyticsEmailSchedulesController < ApplicationController
  before_action :require_admin!
  before_action :load_schedule
  after_action :private_response

  def show
    load_screen
  end

  def update
    saved = @schedule.with_lock do
      @schedule.update(params.require(:analytics_email_schedule).permit(:enabled, :hour, :recipients_text))
    end
    if saved
      redirect_to settings_path, notice: "Agendamento atualizado."
    else
      invalid_settings
    end
  end

  def add_recipient
    if params[:email].blank?
      @schedule.errors.add(:base, "Informe um e-mail válido.")
      invalid_settings
      return
    end
    saved = @schedule.with_lock do
      @schedule.recipients += [params[:email].to_s.strip.downcase]
      @schedule.save
    end
    saved ? redirect_to(settings_path, notice: "Destinatário adicionado.") : invalid_settings
  end

  def remove_recipient
    @schedule.with_lock do
      @schedule.recipients -= [params[:email].to_s.strip.downcase]
      @schedule.enabled = false if @schedule.recipients.empty?
      @schedule.save!
    end
    redirect_to settings_path, notice: "Destinatário removido."
  end

  def preview
    queue_report("preview")
  end

  def send_now
    queue_report("manual")
  end

  private

  def queue_report(kind)
    unless Analytics::ReportEmailConfiguration.ready?
      redirect_to settings_path, alert: "Configure o serviço de e-mail primeiro."
      return
    end
    token = params[:request_token].to_s
    expected = session[:report_dispatch_token].to_s
    unless token.match?(/\A[0-9a-f]{32}\z/) && expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
      redirect_to settings_path, alert: "Solicitação já utilizada ou expirada. Confira o histórico antes de enviar novamente."
      return
    end
    from, to = selected_period
    run_key = "#{kind}-#{token}"
    result = @schedule.with_lock do
      next :duplicate if @schedule.deliveries.exists?(run_key: run_key)
      recent = @schedule.deliveries.where("run_key LIKE ?", "#{kind}-%").where("created_at > ?", 1.minute.ago).exists?
      next :cooldown if recent
      recipients = kind == "preview" ? [current_user.email.downcase] : @schedule.recipients
      next :empty if recipients.empty?
      recipients.each do |email|
        @schedule.deliveries.create!(recipient: email, period_start: from, period_end: to, run_key: run_key)
      end
      :queued
    end
    session[:report_dispatch_token] = SecureRandom.hex(16) if result.in?(%i[queued duplicate])
    if result == :queued
      redirect_to settings_path, notice: kind == "preview" ? "Prévia solicitada para #{current_user.email}. O envio começa em instantes." : "Envio solicitado para os destinatários salvos. Acompanhe o histórico."
    else
      message = { duplicate: "Este envio já foi solicitado. Confira o histórico.", cooldown: "Aguarde um minuto antes de solicitar outro envio deste tipo.", empty: "Adicione pelo menos um destinatário antes de enviar." }.fetch(result)
      redirect_to settings_path, alert: message
    end
  rescue Date::Error, ArgumentError
    redirect_to settings_path, alert: "Escolha um período válido de até 90 dias, sem datas futuras."
  end

  def selected_period
    fallback = Time.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_week(:monday) - 7
    from = params[:from].present? ? Date.iso8601(params[:from].to_s) : fallback
    to = params[:to].present? ? Date.iso8601(params[:to].to_s) : fallback + 6
    raise ArgumentError unless from <= to && (to - from) < 90 && to <= Time.now.utc.to_date
    [from, to]
  end

  def load_screen
    @deliveries = @schedule.deliveries.order(created_at: :desc, id: :desc).limit(60)
    @from, @to = selected_period
    @request_token = session[:report_dispatch_token] ||= SecureRandom.hex(16)
  rescue Date::Error, ArgumentError
    @from = Time.now.utc.to_date - 7
    @to = Time.now.utc.to_date - 1
    @request_token = session[:report_dispatch_token] ||= SecureRandom.hex(16)
  end

  def invalid_settings
    load_screen
    render :show, status: :unprocessable_entity
  end

  def settings_path
    analytics_email_schedule_path(site_id: @site.id, from: params[:from].presence, to: params[:to].presence)
  end

  def load_schedule
    @site = params[:site_id].present? ? Site.find(params[:site_id]) : Site.find_by!(publication_key: "correio-da-manha")
    raise ActiveRecord::RecordNotFound unless @site.active? && @site.correio_source? && !@site.retired_from_hub?
    @site.with_lock { @schedule = AnalyticsEmailSchedule.find_or_create_by!(site: @site) }
  end

  def private_response
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
