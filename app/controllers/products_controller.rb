class ProductsController < ApplicationController
  before_action :set_product, only: %i[show unpublish]
  before_action :require_admin!, only: :unpublish

  def index
    @products = Site.publication_destinations.order(:name).load
    ids = @products.map(&:id)
    @published_counts = SiteArticle.where(site_id: ids, status: "published").group(:site_id).count
    @draft_counts = SiteArticle.where(site_id: ids, status: "draft").group(:site_id).count
    @pending_editions = EditorialEdition.where(site_id: ids, status: "ready").includes(:items).index_by(&:site_id)
    @latest_approvals = EditorialEdition.where(site_id: ids).where.not(approved_at: nil).group(:site_id).maximum(:approved_at)
    @covers = SiteArticle.where(site_id: ids, status: "published").joins(:article)
      .where.not(articles: { image_url: [nil, ""] }).includes(:article)
      .order(published_at: :desc, id: :desc).limit(150).to_a.group_by(&:site_id)
      .transform_values { |records| records.first.article.image_url }
  end

  def show
    @view = params[:view].in?(%w[review work live]) ? params[:view] : "review"
    @edition = @product.editorial_editions.find_by(status: "ready")
    @categories = @product.categories.order(:name).load
    @published = @product.site_articles.where(status: "published")
    originals = Feed.where(site: @product).where("url LIKE ?", "https://hub.cm.com.br/origens/%").select(:id)
    related = Publishing::EditorialPolicy.scope(@product)
    work = related.or(Article.where(feed_id: originals))
      .or(Article.where(id: @product.site_articles.select(:article_id)))
      .where.not(id: @published.select(:article_id)).where.not(status: "ignored")
    @work_count = work.count
    @live_count = @published.count
    @review_count = @edition ? @edition.items.pending.count : 0
    @page = [params[:page].to_i, 1].max
    @recent_edition = @product.editorial_editions.where.not(approved_at: nil).order(approved_at: :desc).first

    if @view == "review"
      @items = @edition.items.pending.includes(article: :feed).order(:id) if @edition
      @review_history = EditorialEditionItem.joins(:editorial_edition)
        .where(editorial_editions: { site_id: @product.id }, decision: %w[approved rejected])
        .includes(:decided_by).order(Arel.sql("decided_at DESC NULLS LAST"), id: :desc).limit(12)
    elsif @view == "work"
      work = work.where(reported_by: current_user) if params[:mine] == "1"
      work = search_articles(work)
      @total = work.count
      @articles = work.includes(:feed, :reported_by).order(updated_at: :desc, id: :desc).limit(24).offset((@page - 1) * 24)
    else
      live = @published.where(article_id: search_articles(Article.all).select(:id))
      live = live.where(category_id: params[:category_id]) if params[:category_id].present?
      @total = live.count
      @distributions = live.includes(:article, :category).order(published_at: :desc, id: :desc).limit(24).offset((@page - 1) * 24)
    end
  end

  def unpublish
    @product.with_lock do
      distribution = @product.site_articles.find(params[:distribution_id])
      distribution.update!(status: "draft", published_at: nil, slot_key: nil, placement: "latest", position: 0)
      ActivityLog.create!(user: current_user, event: "products.unpublish",
        description: "retirou #{distribution.article.title} de #{@product.name}",
        subject_type: "SiteArticle", subject_id: distribution.id)
    end
    redirect_to product_path(@product.publication_key, view: "live"), notice: "Matéria retirada de #{@product.name}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to product_path(@product.publication_key, view: "live"), alert: "Não foi possível retirar a matéria: #{error.record.errors.full_messages.to_sentence}"
  end

  private

  def set_product
    @product = Site.publication_destinations.find_by!(publication_key: params[:publication_key])
    session[:reporter_site_domain] = @product.domain
  end

  def search_articles(scope)
    return scope unless params[:q].present?

    query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
    scope.where("articles.title ILIKE :q OR articles.rewritten_title ILIKE :q OR articles.description ILIKE :q", q: query)
  end
end
