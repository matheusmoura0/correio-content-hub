class PublicationsController < ApplicationController
  before_action :set_site

  def show
    @profile = Publishing::SiteProfile.for(@site)
    @distributions = @site.site_articles.includes(:article, :category).where(status: "published").index_by(&:slot_key)
    @topics = Topic.order(:name)
    @articles = Article.includes(:feed, site_articles: :site).order(created_at: :desc).limit(120)
  end

  def populate
    scope = params[:topic_id].present? ? Topic.find(params[:topic_id]).articles : Article.all
    category = @site.categories.find_by(id: params[:category_id].presence)
    result = Publishing::PopulateSite.call(site: @site, scope:, category:)
    redirect_to publication_path(@site.publication_key),
      notice: "Site populado: #{result.published} matéria(s) publicada(s); #{result.skipped} ignorada(s)."
  end

  def assign
    article = Article.find(params[:article_id])
    category = @site.categories.find_by(id: params[:category_id].presence)
    slot_key = params[:slot_key].to_s
    unless Publishing::SiteProfile.for(@site).automatic_order.include?(slot_key)
      return redirect_to publication_path(@site.publication_key), alert: "Escolha uma posição válida no mock."
    end

    Publishing::PublishArticle.call(article:, site: @site, category:, slot_key:, assignment_mode: "manual")
    redirect_to publication_path(@site.publication_key), notice: "Matéria posicionada no site."
  rescue ActiveRecord::RecordInvalid
    redirect_to publication_path(@site.publication_key), alert: "A matéria não está pronta para publicação. Verifique texto e direitos da imagem."
  end

  def bulk
    ids = Array(params[:article_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
    action = params[:bulk_action].to_s
    return redirect_to(publication_path(@site.publication_key), alert: "Selecione ao menos uma matéria.") if ids.empty?
    return redirect_to(publication_path(@site.publication_key), alert: "Ação em lote inválida.") unless action.in?(%w[publish rewrite_publish unpublish])

    ids.each do |article_id|
      BulkPublicationJob.perform_later(
        article_id:,
        site_id: @site.id,
        action:,
        user_id: current_user.id,
        instructions: params[:rewrite_instructions].to_s.strip.presence,
        category_id: params[:category_id].presence
      )
    end

    label = { "publish" => "publicação", "rewrite_publish" => "reescrita e publicação", "unpublish" => "despublicação" }.fetch(action)
    redirect_to publication_path(@site.publication_key), notice: "#{ids.length} matéria(s) enviadas para #{label} em lote."
  end

  private

  def set_site
    @site = Site.find_by!(publication_key: params[:publication_key])
  end
end
