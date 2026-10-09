class EditorialEditionsController < ApplicationController
  before_action :require_admin!, only: %i[approve reject]
  before_action :set_edition, only: %i[show approve reject]

  def index
    @editions = EditorialEdition.includes(:site, :items).where(status: "ready").order(created_at: :asc)
  end

  def show
    @items = @edition.items.includes(article: :feed).order(:id)
    @categories = @edition.site.categories.order(:name)
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
    ids = Array(params[:item_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
    categories = params.fetch(:categories, ActionController::Parameters.new).permit!.to_h
    Publishing::ApproveEdition.call(edition: @edition, user: current_user, item_ids: ids, categories:)
    redirect_to product_path(@edition.site.publication_key, view: "live"), notice: "Edição aprovada. As matérias selecionadas estão publicadas."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    flash.now[:alert] = error.message
    @items = @edition.items.includes(article: :feed).order(:id)
    @categories = @edition.site.categories.order(:name)
    render :show, status: :unprocessable_entity
  end

  def reject
    @edition.with_lock do
      @edition.update!(status: "rejected") if @edition.status == "ready"
    end
    redirect_to product_path(@edition.site.publication_key), notice: "Proposta descartada. O próximo ciclo poderá preparar outra edição."
  end

  private

  def set_edition
    @edition = EditorialEdition.includes(:site).find(params[:id])
  end
end
