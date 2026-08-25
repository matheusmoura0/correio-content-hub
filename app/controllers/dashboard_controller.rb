class DashboardController < ApplicationController
  def index
    @sites_count = Site.count
    @feeds_count = Feed.count
    @articles_count = Article.count
    @pending_count = Article.where(status: "imported").count
    @topics_count = Topic.where(active: true).count
    @rewritten_count = Article.where.not(rewritten_at: nil).count
    @recent_articles = Article.order(created_at: :desc).limit(10)
    @online_users = User.where("last_seen_at >= ?", 5.minutes.ago).order(:name, :email)
    @recent_activities = ActivityLog.includes(:user).recent.limit(8)
  end
end
