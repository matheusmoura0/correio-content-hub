class ReporterArticlesController < ApplicationController
  before_action :load_site
  before_action :set_article, only: %i[edit update]

  def new
    @article = Article.new(author: current_user.name.presence || current_user.email)
  end

  def create
    @article = Article.new(article_params)
    @article.assign_attributes(
      feed: reporter_feed,
      source_url: "https://hub.cm.com.br/originais/turismo-hoje/#{SecureRandom.uuid}",
      status: "reviewing",
      author: current_user.name.presence || current_user.email,
      reported_by: current_user
    )

    if @article.save
      category = @site.categories.find_by(id: params[:category_id].presence)
      @article.site_articles.create!(site: @site, category:, status: "draft")
      redirect_to edit_reporter_article_path(@article), notice: "Matéria salva como rascunho para revisão editorial."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

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
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def load_site
    @site = Site.find_by!(domain: "turismohoje.com.br", active: true)
  end

  def set_article
    @article = Article.joins(:site_articles)
      .where(site_articles: { site_id: @site.id })
      .find(params[:id])
    return if current_user.admin? || @article.reported_by_id == current_user.id

    redirect_to articles_path(site_domain: @site.domain), alert: "Você só pode editar as matérias que criou."
  end

  def reporter_feed
    Feed.find_or_create_by!(url: "https://hub.cm.com.br/origens/turismo-hoje") do |feed|
      feed.name = "Redação Turismo Hoje"
      feed.active = false
      feed.site = @site
    end
  end

  def article_params
    params.require(:article).permit(:title, :description, :content)
  end
end
