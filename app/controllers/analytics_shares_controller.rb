class AnalyticsSharesController < ApplicationController
  before_action :require_admin!
  before_action :find_publication

  def create
    @site.with_lock { @site.create_analytics_share! unless @site.analytics_share }
    redirect_to analytics_path(site_id: @site.id), notice: "Link de audiência criado."
  end

  def update
    @site.with_lock { @site.analytics_share&.regenerate_token }
    redirect_to analytics_path(site_id: @site.id), notice: "Link substituído. O endereço anterior não funciona mais."
  end

  def destroy
    @site.with_lock { @site.analytics_share&.destroy! }
    redirect_to analytics_path(site_id: @site.id), notice: "Compartilhamento desativado."
  end

  private

  def find_publication
    @site = Site.find(params[:site_id])
    raise ActiveRecord::RecordNotFound unless @site.active? && @site.correio_source? && !@site.retired_from_hub?
  end
end
