require "csv"

class AnalyticsController < ApplicationController
  include AnalyticsDashboard
  before_action :prepare_report

  def index
    load_dashboard
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

    prepare_analytics_report
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
