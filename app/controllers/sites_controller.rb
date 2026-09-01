class SitesController < ApplicationController
  before_action :require_admin!
  before_action :set_site, only: %i[show edit update destroy]

  def index
    @sites = Site.order(:name)
  end

  def show; end

  def new
    @site = Site.new(site_type: "editorial", content_mode: "hub", layout_profile: "standard", active: true)
  end

  def edit; end

  def create
    @site = Site.new(site_params)
    if @site.save
      redirect_to sites_path, notice: "Site criado com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @site.update(site_params)
      redirect_to sites_path, notice: "Site atualizado com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @site.destroy!
    redirect_to sites_path, notice: "Site removido."
  end

  private

  def set_site
    @site = Site.find(params[:id])
  end

  def site_params
    params.require(:site).permit(
      :name, :domain, :publication_key, :site_type, :content_mode,
      :external_provider, :layout_profile, :allowed_origins, :active
    )
  end
end
