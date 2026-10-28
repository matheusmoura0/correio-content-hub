module AnalyticsDashboard
  extend ActiveSupport::Concern

  private

  def load_dashboard
    @total = @report.total_rows
    @per_page = [25, 50, 100].include?(params[:per_page].to_i) ? params[:per_page].to_i : 25
    @page = params[:page].to_i.clamp(1, [(@total / @per_page.to_f).ceil, 1].max)
    @rows = @report.rows(limit: @per_page, offset: (@page - 1) * @per_page)
    @devices = @report.devices
  end

  def prepare_analytics_report
    today = Time.now.utc.to_date
    days = [7, 30, 90].include?(params[:days].to_i) ? params[:days].to_i : 7
    start_date = parse_date(params[:from]) || today - days
    end_date = parse_date(params[:to]) || today - 1
    max_days = @public_dashboard ? 90 : 366
    if start_date > end_date || (end_date - start_date).to_i >= max_days || end_date >= today
      flash.now[:alert] = "Escolha até #{max_days} dias completos, terminando no máximo ontem (UTC)."
      start_date, end_date = today - days, today - 1
    end
    @from = Time.utc(start_date.year, start_date.month, start_date.day)
    @to = Time.utc(end_date.year, end_date.month, end_date.day) + 1.day
    filters = params.permit(:author, :category, :article, :q).to_h
    @report = Analytics::EditorialReport.new(site: @site, from: @from, to: @to, filters: filters,
      dimension: params[:dimension], sort: params[:sort])
    @filter_params = @report.filters.merge(site_id: @site.id, from: start_date.iso8601, to: end_date.iso8601,
      dimension: @report.dimension, sort: @report.sort, per_page: params[:per_page].presence)
  end

  def parse_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end
end
