class ActivityLogsController < ApplicationController
  before_action :require_admin!

  def index
    @users = User.order(:name, :email)
    @activities = ActivityLog.includes(:user).recent.limit(150)
    @activities = @activities.where(user_id: params[:user_id]) if params[:user_id].present?
  end
end
