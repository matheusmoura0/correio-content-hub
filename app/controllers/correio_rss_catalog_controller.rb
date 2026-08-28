class CorreioRssCatalogController < ApplicationController
  before_action :require_admin!

  def create
    result = Correio::SyncRssCatalog.call
    redirect_to feeds_path, notice: [
      "Catálogo do Correio sincronizado.",
      "#{result.feeds_created} canais criados",
      "#{result.feeds_updated} canais atualizados",
      "#{result.topics_created} assuntos criados",
      "#{result.topics_updated} assuntos atualizados"
    ].join(" ")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to feeds_path, alert: "Não foi possível sincronizar o catálogo: #{e.record.errors.full_messages.to_sentence}"
  end
end
