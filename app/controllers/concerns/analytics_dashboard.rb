module AnalyticsDashboard
  extend ActiveSupport::Concern

  private

  def load_dashboard
    if @audience_view
      @reader_insights = @report.reader_insights
      @per_page = 25
      return
    end
    @total = @report.total_rows
    @per_page = [25, 50, 100].include?(params[:per_page].to_i) ? params[:per_page].to_i : 25
    @page = params[:page].to_i.clamp(1, [(@total / @per_page.to_f).ceil, 1].max)
    @rows = @report.rows(limit: @per_page, offset: (@page - 1) * @per_page)
    @devices = @report.devices
  end

  def prepare_analytics_report
    today = Time.now.utc.to_date
    @audience_view = params[:view] == "audience"
    @latest_date = @audience_view ? today : today - 1
    days = [7, 30, 90].include?(params[:days].to_i) ? params[:days].to_i : 7
    start_date = parse_date(params[:from]) || @latest_date - days + 1
    end_date = parse_date(params[:to]) || @latest_date
    max_days = @public_dashboard ? 90 : 366
    if start_date > end_date || (end_date - start_date).to_i >= max_days || end_date > @latest_date
      flash.now[:alert] = "Escolha até #{max_days} dias#{' completos' unless @audience_view}, terminando no máximo em #{@latest_date.strftime('%d/%m/%Y')} (UTC)."
      start_date, end_date = @latest_date - days + 1, @latest_date
    end
    @from = Time.utc(start_date.year, start_date.month, start_date.day)
    @to = Time.utc(end_date.year, end_date.month, end_date.day) + 1.day
    filters = params.permit(:author, :columnist, :category, :article, :q).to_h
    @report = Analytics::EditorialReport.new(site: @site, from: @from, to: @to, filters: filters,
      dimension: @audience_view ? "articles" : params[:dimension], sort: params[:sort])
    @filter_params = @report.filters.merge(site_id: @site.id, from: start_date.iso8601, to: end_date.iso8601,
      dimension: @report.dimension, sort: @report.sort, per_page: params[:per_page].presence)
    @filter_params[:view] = "audience" if @audience_view
  end

  def parse_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end
end
