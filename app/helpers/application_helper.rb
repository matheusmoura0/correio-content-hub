module ApplicationHelper
  ARTICLE_STATUS_LABELS = {
    "imported" => "Coletada",
    "reviewing" => "Em revisão",
    "approved" => "Aprovada",
    "published" => "Publicada",
    "ignored" => "Ignorada"
  }.freeze

  def article_status_label(status)
    ARTICLE_STATUS_LABELS.fetch(status.to_s, status.to_s)
  end

  def article_status_class(status)
    "badge status-#{status}"
  end

  def nav_link_class(path)
    current_page?(path) ? "nav-link active" : "nav-link"
  end
end
