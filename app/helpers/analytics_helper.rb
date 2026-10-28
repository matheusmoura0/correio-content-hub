module AnalyticsHelper
  def public_analytics_pdf_path
    export_public_analytics_path(@filter_params.except(:site_id, :page, :per_page).merge(token: @share.token))
  end

  def analytics_dashboard_path(options = {})
    return analytics_path(options) unless @public_dashboard

    public_analytics_path(options.except(:site_id).merge(token: @share.token))
  end
end
