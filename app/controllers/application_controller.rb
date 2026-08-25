class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  private

  def require_admin!
    redirect_to root_path, alert: "Acesso restrito ao administrador." unless current_user&.admin?
  end
end
