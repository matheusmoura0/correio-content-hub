class PublicationsController < ApplicationController
  MAX_DISTRIBUTIONS = 120
  MAX_AVAILABLE_ARTICLES = 18

  before_action :set_site
  before_action :set_distribution, only: :update

  def index
    @distributions = @site.site_articles
      .includes(:category, article: :feed)
      .order(updated_at: :desc)
      .limit(MAX_DISTRIBUTIONS)
      .to_a
      .select { |distribution| distribution.article.image_url.present? }
      .sort_by { |distribution| [placement_order(distribution.placement), distribution.position.to_i, -distribution.updated_at.to_i] }

    @hero = @distributions.find { |item| item.placement == "hero" }
    @editor_pick = @distributions.find { |item| item.placement == "editor_pick" }
    @published = @distributions.select { |item| item.status == "published" && item.placement == "latest" }
    @drafts = @distributions.select { |item| item.status == "draft" }

    distributed_ids = @distributions.map(&:article_id)
    @available_articles = Article.includes(:feed)
      .where.not(status: "ignored")
      .where.not(id: distributed_ids)
      .where.not(image_url: nil)
      .where.not(image_url: "")
      .order(updated_at: :desc)
      .limit(MAX_AVAILABLE_ARTICLES)
      .to_a
  end

  def create
    article = Article.find(params[:article_id])
    return redirect_to(gastronomy_publications_path, alert: "A matéria precisa ter uma imagem antes de entrar na revista.") if article.image_url.blank?

    distribution = @site.site_articles.find_or_initialize_by(article:)
    distribution.assign_attributes(status: "draft", placement: "latest", position: next_position)
    distribution.save!
    redirect_to gastronomy_publications_path, notice: "Matéria adicionada à fila da revista.", status: :see_other
  end

  def update
    if @distribution.article.image_url.blank?
      return redirect_to gastronomy_publications_path, alert: "Não é possível publicar uma matéria sem imagem.", status: :see_other
    end

    placement = publication_params[:placement].presence || @distribution.placement
    if %w[hero editor_pick].include?(placement)
      @site.site_articles.where(placement:).where.not(id: @distribution.id)
        .update_all(placement: "latest", position: 0, updated_at: Time.current)
    end

    category = publication_params.key?(:category_id) ? @site.categories.find_by(id: publication_params[:category_id].presence) : @distribution.category
    @distribution.assign_attributes(
      placement:,
      position: publication_params.key?(:position) ? publication_params[:position].to_i.clamp(0, 999) : @distribution.position,
      category:,
      status: publication_params[:status].presence || @distribution.status
    )
    @distribution.published_at ||= Time.current if @distribution.status == "published"
    @distribution.published_at = nil if @distribution.status == "draft"
    @distribution.save!
    @distribution.article.update!(status: "published") if @distribution.status == "published"

    message = @distribution.status == "published" ? "Matéria publicada na revista." : "Alterações salvas na mesa editorial."
    redirect_to gastronomy_publications_path, notice: message, status: :see_other
  end

  private

  def set_site
    @site = Site.find_by!(domain: "revistadegastronomia.com.br")
  end

  def set_distribution
    @distribution = @site.site_articles.includes(:article).find(params[:id])
  end

  def publication_params
    params.require(:site_article).permit(:status, :placement, :position, :category_id)
  end

  def next_position
    @site.site_articles.maximum(:position).to_i + 1
  end

  def placement_order(placement)
    { "hero" => 0, "editor_pick" => 1, "latest" => 2 }.fetch(placement, 3)
  end
end
