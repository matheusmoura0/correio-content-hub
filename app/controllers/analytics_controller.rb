require "csv"

class AnalyticsController < ApplicationController
  before_action :prepare_report

  def index
    @total = @report.total_rows
    @per_page = [25, 50, 100].include?(params[:per_page].to_i) ? params[:per_page].to_i : 25
    @page = params[:page].to_i.clamp(1, [(@total / @per_page.to_f).ceil, 1].max)
    @rows = @report.rows(limit: @per_page, offset: (@page - 1) * @per_page)
    @devices = @report.devices
    @top_clicks = @report.top_clicks.first(8)
    @recent_activities = ActivityLog.includes(:user).recent.limit(6).load
  end

  def export
    filename = "metricas-#{@site.publication_key}-#{@report.dimension}-#{@from.to_date}-#{(@to - 1.second).to_date}"
    respond_to do |format|
      format.csv { send_data csv_data, filename: "#{filename}.csv", type: "text/csv; charset=utf-8" }
      format.json { send_data JSON.pretty_generate(@report.as_json), filename: "#{filename}.json", type: "application/json" }
      format.pdf { send_data Analytics::PdfReport.new(@report).call, filename: "#{filename}.pdf", type: "application/pdf", disposition: "attachment" }
    end
  end

  private

  def prepare_report
    @sites = Site.where(active: true).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first
    raise ActiveRecord::RecordNotFound, "Nenhum site ativo cadastrado" unless @site

    # Full UTC days make comparisons reproducible, including exports made later.
    today = Time.now.utc.to_date
    days = [7, 30, 90].include?(params[:days].to_i) ? params[:days].to_i : 7
    start_date = parse_date(params[:from]) || today - days
    end_date = parse_date(params[:to]) || today - 1
    if start_date > end_date || (end_date - start_date).to_i >= 366 || end_date >= today
      flash.now[:alert] = "Escolha até 366 dias completos, terminando no máximo ontem (UTC)."
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

  def csv_data
    columns = %i[key name author category image_url author_image_url views previous_views views_change visitors articles clicks engagement_seconds median_views]
    CSV.generate do |csv|
      csv << ["Publicação", @site.name, "Visão", @report.label, "Início UTC", @from.iso8601, "Fim exclusivo UTC", @to.iso8601].map { |v| csv_cell(v) }
      csv << ["Filtros", @report.filters.to_json].map { |v| csv_cell(v) }
      @report.notes.each { |note| csv << ["Nota", note] }
      csv << columns
      @report.rows(limit: nil).each { |row| csv << columns.map { |key| csv_cell(row[key]) } }
    end
  end

  def csv_cell(value)
    value.is_a?(String) && value.match?(/\A[\s]*[=+@-]/) ? "'#{value}" : value
  end
end
