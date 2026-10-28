module AnalyticsHelper
  def analytics_dashboard_path(options = {})
    return analytics_path(options) unless @public_dashboard

    public_analytics_path(options.except(:site_id).merge(token: @share.token))
  end
end
