class ArticlesController < ApplicationController
  before_action :set_article, only: %i[show update publish_to_gastronomy unpublish_from_gastronomy]

  def index
    @site = Site.find_by(domain: params[:site_domain]) if params[:site_domain].present?
    @articles = Article.includes(:feed, :topics, site_articles: [:site, :category]).order(created_at: :desc)
    @articles = @articles.joins(:site_articles).where(site_articles: { site_id: @site.id }).distinct if @site
    @articles = @articles.where(status: params[:status]) if params[:status].present?
    @articles = @articles.joins(:topic_articles).where(topic_articles: { topic_id: params[:topic_id] }).distinct if params[:topic_id].present?
    if params[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      @articles = @articles.where("articles.title ILIKE :query OR articles.description ILIKE :query OR articles.rewritten_title ILIKE :query", query:)
    end
  end

  def show
    load_sites
  end

  def update
    @article.assign_attributes(article_params)
    apply_image_rights_review if params[:image_rights_review].present?

    if @article.save
      sync_sites if params.key?(:site_ids)
      revoke_unsafe_gastronomy_distribution if params[:image_rights_review].present? && !@article.licensed_image_ready?
      notice = params[:image_rights_review].present? ? "Dados e direitos da imagem atualizados." : "Matéria atualizada."
      redirect_to @article, notice:
    else
      load_sites
      render :show, status: :unprocessable_entity
    end
  end

  def publish_to_gastronomy
    site = gastronomy_site
    return redirect_to(@article, alert: "Confirme a origem e os direitos da imagem antes de publicar.") unless @article.licensed_image_ready?

    settings = gastronomy_params
    placement = SiteArticle::PLACEMENTS.include?(settings[:placement]) ? settings[:placement] : "latest"
    category = site.categories.find_by(id: settings[:category_id].presence)

    Article.transaction do
      if %w[hero editor_pick].include?(placement)
        site.site_articles.where(placement:).where.not(article_id: @article.id)
          .update_all(placement: "latest", position: 0, updated_at: Time.current)
      end

      @article.update!(status: "published")
      distribution = @article.site_articles.find_or_initialize_by(site:)
      distribution.assign_attributes(
        status: "published",
        placement:,
        category:,
        position: settings[:position].to_i.clamp(0, 999),
        published_at: Time.current
      )
      distribution.save!
    end

    redirect_to @article, notice: "Matéria publicada na Revista de Gastronomia."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to @article, alert: "Não foi possível publicar: #{error.record.errors.full_messages.to_sentence}"
  end

  def unpublish_from_gastronomy
    distribution = @article.site_articles.find_by(site: gastronomy_site)
    distribution&.update!(status: "draft", published_at: nil)
    redirect_to @article, notice: "Matéria retirada da Revista de Gastronomia."
  end

  private

  def set_article
    @article = Article.find(params[:id])
  end

  def load_sites
    @sites = Site.where(active: true).includes(:categories).order(:name)
    @gastronomy_site = @sites.find { |site| site.domain == "revistadegastronomia.com.br" }
    @gastronomy_distribution = @article.site_articles.find_by(site: @gastronomy_site) if @gastronomy_site
  end

  def gastronomy_site
    Site.find_by!(domain: "revistadegastronomia.com.br")
  end

  def article_params
    params.require(:article).permit(:status, :rewritten_title, :rewritten_content, :image_url, :image_source_url, :image_author, :image_license, :image_license_url)
  end

  def gastronomy_params
    params.fetch(:publication, ActionController::Parameters.new).permit(:placement, :category_id, :position)
  end

  def apply_image_rights_review
    if params[:image_rights_confirmed] == "1"
      @article.image_rights_confirmed_at = Time.current
      @article.image_rights_confirmed_by = current_user
    else
      @article.image_rights_confirmed_at = nil
      @article.image_rights_confirmed_by = nil
    end
  end

  def revoke_unsafe_gastronomy_distribution
    distribution = @article.site_articles.find_by(site: Site.find_by(domain: "revistadegastronomia.com.br"))
    distribution&.update!(status: "draft", published_at: nil)
  end

  def sync_sites
    placements = params.fetch(:site_placements, {}).to_unsafe_h
    positions = params.fetch(:site_positions, {}).to_unsafe_h
    categories = params.fetch(:site_categories, {}).to_unsafe_h
    selected_ids = Array(params[:site_ids]).reject(&:blank?).map(&:to_i)
    @article.site_articles.where.not(site_id: selected_ids).destroy_all

    selected_ids.each do |site_id|
      site = Site.find(site_id)
      next if site.domain == "revistadegastronomia.com.br"

      distribution = @article.site_articles.find_or_initialize_by(site_id:)
      placement = placements.fetch(site_id.to_s, "latest")
      placement = "latest" unless SiteArticle::PLACEMENTS.include?(placement)
      category = Category.find_by(id: categories[site_id.to_s].presence, site_id:)
      distribution.assign_attributes(
        placement:,
        position: positions.fetch(site_id.to_s, 0).to_i.clamp(0, 999),
        category:,
        status: @article.status == "published" ? "published" : "draft"
      )
      distribution.published_at ||= Time.current if distribution.status == "published"
      distribution.published_at = nil if distribution.status == "draft"
      distribution.save!
    end
  end
end
