class ArticlesController < ApplicationController
  before_action :set_article, only: %i[show update]

  def index
    @articles = Article.includes(:feed, :topics).order(created_at: :desc)
    @articles = @articles.where(status: params[:status]) if params[:status].present?
    @articles = @articles.joins(:topic_articles).where(topic_articles: { topic_id: params[:topic_id] }).distinct if params[:topic_id].present?
    if params[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      @articles = @articles.where("articles.title ILIKE :query OR articles.description ILIKE :query", query:)
    end
  end

  def show
    @sites = Site.where(active: true).order(:name)
  end

  def update
    if @article.update(article_params)
      sync_sites if params.key?(:site_ids)
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
    params.require(:article).permit(:status, :rewritten_title, :rewritten_content)
  end

  def sync_sites
    placements = params.fetch(:site_placements, {}).to_unsafe_h
    selected_ids = Array(params[:site_ids]).reject(&:blank?).map(&:to_i)
    @article.site_articles.where.not(site_id: selected_ids).destroy_all

    selected_ids.each do |site_id|
      distribution = @article.site_articles.find_or_initialize_by(site_id:)
      placement = placements.fetch(site_id.to_s, "latest")
      placement = "latest" unless SiteArticle::PLACEMENTS.include?(placement)
      if %w[hero editor_pick].include?(placement)
        SiteArticle.where(site_id:, placement:).where.not(article_id: @article.id).update_all(placement: "latest", position: 0)
      end
      distribution.placement = placement
      distribution.status = @article.status == "published" ? "published" : "draft"
      distribution.published_at = Time.current if distribution.status == "published" && distribution.published_at.blank?
      distribution.published_at = nil if distribution.status == "draft"
      distribution.save!
    end
  end
end
