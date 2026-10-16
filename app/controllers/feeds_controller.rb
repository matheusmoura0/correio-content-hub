class FeedsController < ApplicationController
  before_action :require_admin!
  before_action :set_feed, only: %i[show edit update destroy import_feed]

  def index
    @feeds = Feed.includes(:site, :category, :articles).order(:name).load.to_a
  rescue StandardError => error
    Rails.logger.error("Feeds index unavailable: #{error.class}: #{error.message}")
    @feeds = []
    flash.now[:alert] = "Os canais RSS estão temporariamente indisponíveis. Verifique as migrações do banco."
  end

  def show; end

  def new
    @feed = Feed.new
  end

  def edit; end

  def create
    @feed = Feed.new(feed_params)
    if @feed.save
      redirect_to feeds_path, notice: "Feed criado com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @feed.update(feed_params)
      redirect_to feeds_path, notice: "Feed atualizado com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @feed.destroy!
    redirect_to feeds_path, notice: "Feed removido."
  end

  def import_feed
    result = Rss::ImportFeed.call(@feed)
    redirect_to feeds_path, notice: "Importação concluída: #{result.imported} novas, #{result.skipped} ignoradas."
  rescue StandardError => e
    redirect_to feeds_path, alert: "Falha ao importar feed: #{e.message}"
  end

  private

  def set_feed
    @feed = Feed.find(params[:id])
  end

  def feed_params
    params.require(:feed).permit(:name, :url, :site_id, :category_id, :active)
  end
end
