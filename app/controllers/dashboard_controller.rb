class DashboardController < ApplicationController
  def index
    @sites_count = safely(0, "sites_count") { Site.where(active: true).count }
    @feeds_count = safely(0, "feeds_count") { Feed.where(active: true).count }
    @articles_count = safely(0, "articles_count") { Article.count }
    @pending_count = safely(0, "pending_count") { Article.where(status: "imported").count }
    @published_count = safely(0, "published_count") { SiteArticle.where(status: "published").count }
    @topics_count = safely(0, "topics_count") { Topic.where(active: true).count }
    @recent_articles = safely(Article.none, "recent_articles") {
      Article.includes(:feed).order(created_at: :desc).limit(10)
    }
    @online_users = safely(User.none, "online_users") {
      User.where("last_seen_at >= ?", 5.minutes.ago).order(:name, :email)
    }
    @recent_activities = safely(ActivityLog.none, "recent_activities") {
      ActivityLog.includes(:user).recent.limit(8)
    }
  end

  private

  def safely(fallback, section)
    yield
  rescue StandardError => error
    Rails.logger.error(
      "Dashboard section #{section} unavailable: #{error.class}: #{error.message}"
    )
    fallback
  end
end
