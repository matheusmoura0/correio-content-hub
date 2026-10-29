class AnalyticsEmailSchedulesController < ApplicationController
  before_action :require_admin!
  before_action :load_schedule
  after_action :private_response

  def show
    @deliveries = @schedule.deliveries.order(created_at: :desc, id: :desc).limit(60)
  end

  def update
    if @schedule.update(params.require(:analytics_email_schedule).permit(:enabled, :hour, :recipients_text))
      redirect_to analytics_email_schedule_path(site_id: @site.id), notice: "Envio semanal atualizado."
    else
      @deliveries = @schedule.deliveries.order(created_at: :desc, id: :desc).limit(60)
      render :show, status: :unprocessable_entity
    end
  end

  def preview
    unless Analytics::ReportEmailConfiguration.ready?
      redirect_to analytics_email_schedule_path(site_id: @site.id), alert: "Configure o serviço de e-mail primeiro."
      return
    end
    queued = @schedule.with_lock do
      recent = @schedule.deliveries.where.not(run_key: "weekly").where("created_at > ?", 30.minutes.ago).exists?
      next false if recent

      @schedule.deliveries.create!(recipient: current_user.email.downcase,
        period_start: Time.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_week(:monday) - 7,
        run_key: "preview-#{SecureRandom.uuid}")
      true
    end
    redirect_to analytics_email_schedule_path(site_id: @site.id),
      notice: queued ? "Prévia na fila para seu e-mail. O processamento ocorre em até 30 minutos." : "Uma prévia já foi solicitada nos últimos 30 minutos."
  end

  private

  def load_schedule
    @site = Site.find(params[:site_id])
    raise ActiveRecord::RecordNotFound unless @site.active? && @site.correio_source? && !@site.retired_from_hub?
    @site.with_lock { @schedule = AnalyticsEmailSchedule.find_or_create_by!(site: @site) }
  end

  def private_response
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
