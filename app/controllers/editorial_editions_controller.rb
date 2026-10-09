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
      redirect_to editorial_edition_path(edition)
    else
      redirect_to editorial_editions_path, notice: "Sem novas matérias prontas ou posições automáticas disponíveis para #{site.name}."
    end
  end

  def approve
    ids = Array(params[:item_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
    categories = params.fetch(:categories, ActionController::Parameters.new).permit!.to_h
    Publishing::ApproveEdition.call(edition: @edition, user: current_user, item_ids: ids, categories:)
    redirect_to editorial_edition_path(@edition), notice: "Edição aprovada. As matérias selecionadas estão publicadas."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to editorial_edition_path(@edition), alert: error.message
  end

  def reject
    @edition.with_lock do
      @edition.update!(status: "rejected") if @edition.status == "ready"
    end
    redirect_to editorial_editions_path, notice: "Proposta descartada. O próximo ciclo poderá preparar outra edição."
  end

  private

  def set_edition
    @edition = EditorialEdition.includes(:site).find(params[:id])
  end
end
