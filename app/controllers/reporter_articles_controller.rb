class ReporterArticlesController < ApplicationController
  before_action :load_sites
  before_action :set_article, only: %i[edit update]

  def new
    @site = selected_site
    @article = Article.new(author: current_user.name.presence || current_user.email)
  end

  def create
    @site = selected_site
    @article = Article.new(article_params)
    @article.assign_attributes(
      feed: reporter_feed,
      source_url: "https://hub.cm.com.br/originais/#{@site.publication_key}/#{SecureRandom.uuid}",
      status: "reviewing",
      author: current_user.name.presence || current_user.email,
      reported_by: current_user
    )

    saved = Article.transaction do
      next false unless @article.save

      category = @site.categories.find_by(id: params[:category_id].presence)
      @article.site_articles.create!(site: @site, category:, status: "draft")
      true
    end

    if saved
      redirect_to edit_reporter_article_path(@article), notice: "Matéria salva como rascunho para revisão editorial."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    render :new
  end

  def update
    saved = Article.transaction do
      was_published = @article.status == "published"
      @article.assign_attributes(article_params)
      @article.status = "reviewing" if was_published
      next false unless @article.save

      category = @site.categories.find_by(id: params[:category_id].presence)
      distribution = @article.site_articles.find_or_initialize_by(site: @site)
      distribution.assign_attributes(status: "draft", published_at: nil) if was_published
      distribution.update!(category:)
      true
    end

    if saved
      redirect_to edit_reporter_article_path(@article), notice: "Rascunho atualizado para revisão."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_sites
    @sites = Site.publication_destinations.order(:name).includes(:categories).load
  end

  def selected_site
    requested_id = params[:site_id].presence
    requested_id ? @sites.find { |site| site.id == requested_id.to_i } || @sites.first! : @sites.first!
  end

  def set_article
    @article = Article.includes(site_articles: :site).find(params[:id])
    @site = @article.site_articles.first&.site
    return redirect_to(articles_path, alert: "A matéria não possui uma publicação de destino.") unless @site
    return if current_user.admin? || @article.reported_by_id == current_user.id

    redirect_to articles_path(site_domain: @site.domain), alert: "Você só pode editar as matérias que criou."
  end

  def reporter_feed
    feed_url = @site.domain == "turismohoje.com.br" ? "https://hub.cm.com.br/origens/turismo-hoje" : "https://hub.cm.com.br/origens/editorial/#{@site.publication_key}"
    Feed.find_or_create_by!(url: feed_url) do |feed|
      feed.name = "Redação #{@site.name}"
      feed.active = false
      feed.site = @site
    end
  end

  def article_params
    params.require(:article).permit(:title, :description, :content)
  end
end
