class PublicAnalyticsController < ActionController::Base
  include AnalyticsDashboard
  layout "public_analytics"
  before_action :protect_shared_response

  def show
    @share = AnalyticsShare.includes(:site).find_by(token: params[:token].to_s)
    unless @share&.available?
      render :unavailable, formats: [:html], status: :not_found
      return
    end

    @public_dashboard = true
    @site = @share.site
    prepare_analytics_report
    load_dashboard
    render "analytics/index", formats: [:html]
  end

  private

  def protect_shared_response
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("X-Frame-Options", "DENY")
  end
end
