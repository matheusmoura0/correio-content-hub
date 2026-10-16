class PublicationsController < ApplicationController
  before_action :set_site
  before_action :require_admin!, only: %i[clear populate assign bulk]

  def show
    @profile = Publishing::SiteProfile.for(@site)
    @pending_edition = EditorialEdition.find_by(site: @site, status: "ready")
    @distributions = @site.site_articles.includes(:article, :category).where(status: "published").index_by(&:slot_key)
    @topics = Topic.order(:name)
    @articles = Publishing::EditorialPolicy.scope(@site).includes(:feed, site_articles: :site).order(created_at: :desc).limit(120)
    @selected_article = Publishing::EditorialPolicy.scope(@site).find_by(id: params[:article_id]) if params[:article_id].present?
    @articles = [@selected_article, *@articles.to_a].compact.uniq if @selected_article
  end

  def populate
    scope = params[:topic_id].present? ? Topic.find(params[:topic_id]).articles : Article.all
    category = @site.categories.find_by(id: params[:category_id].presence)
    target = params[:target] == "section" ? "section" : "home"
    if target == "section" && (@site.layout_profile != "icaro" || category.nil? || params[:topic_id].blank?)
      return redirect_to publication_path(@site.publication_key), alert: "Para preencher uma editoria, escolha a página e uma pesquisa temática."
    end
    result = Publishing::PopulateSite.call(site: @site, scope:, category:, target:)
    redirect_to publication_path(@site.publication_key),
      notice: "Site populado: #{result.published} de #{result.capacity} posição(ões) automática(s) preenchida(s); #{result.eligible} matéria(s) elegível(is); #{result.skipped} ignorada(s)."
  end

  def assign
    article = Article.find(params[:article_id])
    category = @site.categories.find_by(id: params[:category_id].presence)
    slot_key = params[:slot_key].to_s
    unless Publishing::SiteProfile.slot_keys(@site).include?(slot_key)
      return redirect_to publication_path(@site.publication_key), alert: "Escolha uma posição válida no mock."
    end

    if @site.layout_profile == "icaro"
      slug = Publishing::SiteProfile::ICARO_SECTIONS.keys.find { |key| Publishing::SiteProfile.icaro_section_slots(key).include?(slot_key) }
      slug ||= "aviacao" if slot_key.start_with?("icaro_aviation_")
      category = @site.categories.find_by!(slug:) if slug
    end

    Publishing::PublishArticle.call(article:, site: @site, category:, slot_key:, assignment_mode: "manual")
    redirect_to publication_path(@site.publication_key), notice: "Matéria posicionada no site."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to publication_path(@site.publication_key), alert: error.record.errors.full_messages.to_sentence.presence || "A matéria não está pronta para publicação. Verifique texto e direitos da imagem."
  end

  def bulk
    ids = Array(params[:article_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
    action = params[:bulk_action].to_s
    return redirect_to(publication_path(@site.publication_key), alert: "Selecione ao menos uma matéria.") if ids.empty?
    return redirect_to(publication_path(@site.publication_key), alert: "Ação em lote inválida.") unless action.in?(%w[publish rewrite_publish unpublish])
    if action != "unpublish" && Publishing::EditorialPolicy.scope(@site, Article.where(id: ids)).count != ids.size
      return redirect_to(publication_path(@site.publication_key), alert: "Selecione apenas matérias relacionadas à linha editorial de #{@site.name}.")
    end

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

  def clear
    removed = @site.with_lock do
      @site.site_articles.where(status: "published").update_all(
        status: "draft",
        published_at: nil,
        slot_key: nil,
        placement: "latest",
        position: 0,
        assignment_mode: "automatic",
        updated_at: Time.current
      )
    end
    redirect_to publication_path(@site.publication_key), notice: "Site limpo: #{removed} matéria(s) retirada(s) da publicação. O acervo foi preservado."
  end

  private

  def set_site
    @site = Site.publication_destinations.find_by!(publication_key: params[:publication_key])
  end
end
