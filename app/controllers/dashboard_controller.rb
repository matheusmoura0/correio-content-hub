class DashboardController < ApplicationController
  def index
    @sites_count = Site.where(active: true).count
    @feeds_count = Feed.where(active: true).count
    @articles_count = Article.count
    @pending_count = Article.where(status: "imported").count
    @published_count = SiteArticle.where(status: "published").count
    @topics_count = Topic.where(active: true).count
    @recent_articles = Article.includes(:feed).order(created_at: :desc).limit(10)
    @online_users = User.where("last_seen_at >= ?", 5.minutes.ago).order(:name, :email)
    @recent_activities = ActivityLog.includes(:user).recent.limit(8)
  end
end
