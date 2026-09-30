class CorreioRssCatalogController < ApplicationController
  before_action :require_admin!

  def create
    result = Correio::SyncRssCatalog.call
    redirect_to feeds_path, notice: [
      "Canais RSS do Correio sincronizados.",
      "#{result.feeds_created} canais criados.",
      "#{result.feeds_updated} canais atualizados.",
      "A importação continua manual e sem filtro de palavras-chave."
    ].join(" ")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to feeds_path, alert: "Não foi possível sincronizar os canais: #{e.record.errors.full_messages.to_sentence}"
  end
end
