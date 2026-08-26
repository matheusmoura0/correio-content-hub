class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :track_presence
  after_action :record_activity

  ACTIVITY_DESCRIPTIONS = {
    ["topics", "create"] => "criou uma pesquisa",
    ["topics", "update"] => "atualizou uma pesquisa",
    ["topics", "destroy"] => "excluiu uma pesquisa",
    ["topics", "run"] => "executou uma pesca de matérias",
    ["article_rewrites", "create"] => "reescreveu uma matéria com IA",
    ["articles", "update"] => "atualizou a revisão de uma matéria",
    ["publications", "create"] => "adicionou uma matéria à fila da Revista de Gastronomia",
    ["publications", "update"] => "atualizou a publicação na Revista de Gastronomia",
    ["feeds", "create"] => "adicionou uma fonte RSS",
    ["feeds", "update"] => "atualizou uma fonte RSS",
    ["feeds", "destroy"] => "excluiu uma fonte RSS",
    ["feeds", "import_feed"] => "importou matérias de uma fonte RSS",
    ["sites", "create"] => "adicionou um site",
    ["sites", "update"] => "atualizou um site",
    ["sites", "destroy"] => "excluiu um site",
    ["categories", "create"] => "criou uma categoria",
    ["categories", "update"] => "atualizou uma categoria",
    ["categories", "destroy"] => "excluiu uma categoria",
    ["users", "create"] => "criou um usuário",
    ["users", "update"] => "atualizou um usuário",
    ["users", "destroy"] => "excluiu um usuário"
  }.freeze

  private

  def track_presence
    return unless current_user
    return if current_user.last_seen_at.present? && current_user.last_seen_at > 1.minute.ago

    current_user.update_column(:last_seen_at, Time.current)
  end

  def record_activity
    return unless current_user && (response.successful? || response.redirect?)

    description = ACTIVITY_DESCRIPTIONS[[controller_name, action_name]]
    return if description.blank?

    subject = activity_subject
    ActivityLog.create!(
      user: current_user,
      event: "#{controller_name}.#{action_name}",
      description: [description, activity_subject_label(subject)].compact.join(": "),
      subject_type: subject&.class&.name,
      subject_id: subject&.id
    )
  rescue StandardError => error
    Rails.logger.error("Falha ao registrar atividade: #{error.class}: #{error.message}")
  end

  def activity_subject
    %i[@topic @article @feed @site @category @user].filter_map { |name| instance_variable_get(name) }.first
  end

  def activity_subject_label(subject)
    return if subject.blank?

    value = subject.try(:title).presence || subject.try(:name).presence || subject.try(:email).presence
    value.to_s.first(120).presence
  end

  def require_admin!
    redirect_to root_path, alert: "Acesso restrito ao administrador." unless current_user&.admin?
  end
end
