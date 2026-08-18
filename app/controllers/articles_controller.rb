class ArticlesController < ApplicationController
  before_action :set_article, only: %i[show update]

  def index
    @articles = Article.includes(:feed).order(created_at: :desc)
    @articles = @articles.where(status: params[:status]) if params[:status].present?
  end

  def show
    @sites = Site.where(active: true).order(:name)
  end

  def update
    if @article.update(article_params)
      sync_sites if params[:site_ids]
      redirect_to @article, notice: "Matéria atualizada."
    else
      @sites = Site.where(active: true).order(:name)
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_article
    @article = Article.find(params[:id])
  end

  def article_params
    params.require(:article).permit(:status)
  end

  def sync_sites
    selected_ids = Array(params[:site_ids]).reject(&:blank?).map(&:to_i)
    @article.site_articles.where.not(site_id: selected_ids).destroy_all

    selected_ids.each do |site_id|
      @article.site_articles.find_or_create_by!(site_id:) do |distribution|
        distribution.status = "draft"
      end
    end
  end
end
