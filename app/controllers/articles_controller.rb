class ArticlesController < ApplicationController
  before_action :set_article, only: %i[show update publish_to_gastronomy unpublish_from_gastronomy]
  before_action :require_admin!, only: :destroy_bulk

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

  def destroy_bulk
    ids = Array(params[:article_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
    return redirect_back(fallback_location: articles_path, alert: "Selecione ao menos uma matéria para excluir.") if ids.empty?

    articles = Article.where(id: ids)
    deleted = articles.count
    Article.transaction { articles.find_each(&:destroy!) }
    redirect_back fallback_location: articles_path, notice: "#{deleted} matéria(s) excluída(s) do Hub e retirada(s) dos sites associados."
  rescue ActiveRecord::RecordNotDestroyed => error
    redirect_back fallback_location: articles_path, alert: "Não foi possível concluir a exclusão: #{error.record.errors.full_messages.to_sentence}"
  end

  def publish_to_gastronomy
    site = gastronomy_site
    return redirect_to(@article, alert: "A matéria ainda não está pronta para publicação.") unless @article.publication_ready?

    settings = gastronomy_params
    slot_key = settings[:slot_key].presence
    slot_key = nil unless SiteArticle::SLOT_KEYS.include?(slot_key)
    category = site.categories.find_by(id: settings[:category_id].presence)
    if SiteArticle.category_slot?(slot_key) && category.nil?
      return redirect_to(@article, alert: "Escolha uma editoria para usar uma posição da página de editoria.")
    end

    Article.transaction do
      distribution = @article.site_articles.find_or_initialize_by(site:)
      if slot_key
        occupied = site.site_articles.where(status: "published", slot_key:).where.not(article_id: @article.id)
        occupied = occupied.where(category:) if SiteArticle.category_slot?(slot_key)
        occupied.update_all(slot_key: nil, placement: "latest", position: 0, assignment_mode: "automatic", updated_at: Time.current)
        distribution.slot_key = slot_key
        distribution.assignment_mode = "manual"
        distribution.placement = SiteArticle.placement_for(slot_key)
        distribution.position = SiteArticle::SLOT_KEYS.index(slot_key).to_i + 1
      else
        SiteArticle.claim_automatic_slot!(distribution)
      end

      @article.update!(status: "published")
      distribution.assign_attributes(
        status: "published",
        category:,
        display_title: settings[:display_title].presence,
        image_focus_x: settings[:image_focus_x].to_i.clamp(0, 100),
        image_focus_y: settings[:image_focus_y].to_i.clamp(0, 100),
        image_zoom: settings[:image_zoom].to_f.clamp(1.0, 2.0),
        published_at: Time.current
      )
      distribution.save!
    end

    message = slot_key ? "Matéria publicada em #{SiteArticle::SLOT_LABELS[slot_key]}." : "Matéria publicada em uma posição automática."
    redirect_to @article, notice: message
  rescue ActiveRecord::RecordInvalid => error
    redirect_to @article, alert: "Não foi possível publicar: #{error.record.errors.full_messages.to_sentence}"
  end

  def unpublish_from_gastronomy
    distribution = @article.site_articles.find_by(site: gastronomy_site)
    distribution&.update!(status: "draft", published_at: nil, slot_key: nil)
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
    @gastronomy_slot_occupancy = @gastronomy_site&.site_articles&.includes(:article)&.where(status: "published", slot_key: SiteArticle::SLOT_KEYS)&.index_by(&:slot_key) || {}
  end

  def gastronomy_site
    Site.find_by!(domain: "revistadegastronomia.com.br")
  end

  def article_params
    params.require(:article).permit(:status, :rewritten_title, :rewritten_content, :image_url, :image_source_url, :image_author, :image_license, :image_license_url)
  end

  def gastronomy_params
    params.fetch(:publication, ActionController::Parameters.new).permit(:slot_key, :category_id, :display_title, :image_focus_x, :image_focus_y, :image_zoom)
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
    distribution&.update!(status: "draft", published_at: nil, slot_key: nil)
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
