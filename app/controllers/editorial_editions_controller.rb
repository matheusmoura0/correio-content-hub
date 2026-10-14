class EditorialEditionsController < ApplicationController
  before_action :require_admin!, only: %i[approve reject]
  before_action :set_edition, only: %i[show approve reject]

  def index
    @editions = EditorialEdition.includes(:site, :items).where(status: "ready").order(created_at: :asc)
  end

  def show
    load_review
  end

  def prepare
    site = Site.publication_destinations.find(params[:site_id])
    edition = Publishing::PrepareEdition.call(site)
    if edition
      redirect_to params[:product_context] == "1" ? product_path(site.publication_key) : editorial_edition_path(edition)
    else
      redirect_to product_path(site.publication_key), notice: "Sem novas matérias prontas ou posições automáticas disponíveis para #{site.name}."
    end
  end

  def approve
    categories = params.fetch(:categories, ActionController::Parameters.new).permit!.to_h
    Publishing::ApproveEdition.call(edition: @edition, user: current_user, item_ids: decision_ids, categories:,
      page_digest: params[:page_digest], article_digests: decision_digests)
    redirect_to product_path(@edition.site.publication_key), notice: "Matérias aprovadas e publicadas. As demais sugestões continuam aguardando sua decisão."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    flash.now[:alert] = error.message
    @edition.reload
    load_review
    render :show, status: :unprocessable_entity
  end

  def reject
    Publishing::RejectSuggestions.call(edition: @edition, user: current_user, item_ids: decision_ids, article_digests: decision_digests)
    redirect_to product_path(@edition.site.publication_key), notice: "Sugestões recusadas. Estas matérias não serão sugeridas novamente neste produto."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    flash.now[:alert] = error.message
    @edition.reload
    load_review
    render :show, status: :unprocessable_entity
  end

  private

  def decision_ids
    ids = params[:item_id].present? ? [params[:item_id]] : Array(params[:item_ids])
    ids.filter_map { |id| Integer(id, exception: false) }.uniq
  end

  def decision_digests
    params.fetch(:article_digests, ActionController::Parameters.new).permit!.to_h
  end

  def load_review
    @items = (@edition.status == "ready" ? @edition.items.pending : @edition.items).includes(article: :feed).order(:id)
    @categories = @edition.site.categories.order(:name)
  end

  def set_edition
    @edition = EditorialEdition.includes(:site).find(params[:id])
  end
end
