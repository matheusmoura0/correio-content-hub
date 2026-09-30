class DashboardController < ApplicationController
  def index
    @sites_count = safely(0, "sites_count") { Site.where(active: true).count }
    @feeds_count = safely(0, "feeds_count") { Feed.where(active: true).count }
    @articles_count = safely(0, "articles_count") { Article.count }
    @pending_count = safely(0, "pending_count") { Article.where(status: "imported").count }
    @published_count = safely(0, "published_count") { SiteArticle.where(status: "published").count }
    @topics_count = safely(0, "topics_count") { Topic.where(active: true).count }
    @recent_articles = safely([], "recent_articles") do
      Article.includes(:feed, :rewritten_by, site_articles: :site).order(created_at: :desc).limit(36).load.to_a
    end
    @workflow_articles = {
      entries: @recent_articles.select { |article| article.status == "imported" }.first(10),
      reviewing: @recent_articles.select { |article| article.status == "reviewing" }.first(10),
      ready: @recent_articles.select { |article| article.status.in?(%w[approved published]) }.first(10)
    }
    @workflow_counts = safely({}, "workflow_counts") { Article.group(:status).count }
    @selected_article = @workflow_articles[:reviewing].first || @workflow_articles[:entries].first || @recent_articles.first
    @publication_sites = safely([], "publication_sites") do
      Site.publication_destinations.order(:name).limit(7).load.to_a
    end
    @online_users = safely([], "online_users") { User.where("last_seen_at >= ?", 5.minutes.ago).order(:name, :email).load.to_a }
    @recent_activities = safely([], "recent_activities") { ActivityLog.includes(:user).recent.limit(8).load.to_a }
  end

  private

  def safely(fallback, section)
    yield
  rescue StandardError => error
    Rails.logger.error("Dashboard section #{section} unavailable: #{error.class}: #{error.message}")
    fallback
  end
end
