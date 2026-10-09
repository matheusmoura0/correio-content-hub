class ReporterArticlesController < ApplicationController
  before_action :load_sites
  before_action :set_article, only: %i[edit update]

  def new
    @site = selected_site
    @fixed_destination = params[:site_id].present?
    @article = Article.new(author: current_user.name.presence || current_user.email)
  end

  def create
    @site = selected_site
    @fixed_destination = params[:fixed_destination] == "1"
    @article = Article.new(article_params)
    @article.assign_attributes(
      feed: reporter_feed,
      source_url: "https://hub.cm.com.br/originais/#{@site.publication_key}/#{SecureRandom.uuid}",
      status: "reviewing",
      author: current_user.name.presence || current_user.email,
      reported_by: current_user
    )

    category = @site.categories.find_by(id: params[:category_id].presence)
    @article.errors.add(:base, "Escolha uma editoria de #{@site.name}.") unless category
    saved = category && Article.transaction do
      next false unless @article.save

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
    category = @site.categories.find_by(id: params[:category_id].presence)
    @article.assign_attributes(article_params)
    @article.errors.add(:base, "Escolha uma editoria de #{@site.name}.") unless category
    saved = category && Article.transaction do
      was_published = @article.status == "published"
      @article.assign_attributes(article_params)
      @article.status = "reviewing" if was_published
      next false unless @article.save

      if was_published
        @article.site_articles.where(status: "published").update_all(
          status: "draft", published_at: nil, slot_key: nil, placement: "latest", position: 0, updated_at: Time.current
        )
      end
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
    return @sites.find { |site| site.id == requested_id.to_i } || raise(ActiveRecord::RecordNotFound) if requested_id

    @sites.find { |site| site.domain == session[:reporter_site_domain] } || @sites.first!
  end

  def set_article
    @article = Article.includes(site_articles: :site).find(params[:id])
    @site = @article.feed.site if @article.feed.hub_authored?
    @site ||= @article.site_articles.first&.site
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
