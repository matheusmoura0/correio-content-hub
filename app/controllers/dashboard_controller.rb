class DashboardController < ApplicationController
  def index
    @sites_count = Site.count
    @feeds_count = Feed.count
    @articles_count = Article.count
    @pending_count = Article.where(status: "imported").count
    @recent_articles = Article.order(created_at: :desc).limit(10)
  end
end
