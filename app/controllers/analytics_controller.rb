require "csv"

class AnalyticsController < ApplicationController
  PERIODS = [7, 30, 90].freeze

  before_action :prepare_report

  def index; end

  def export
    filename = "metricas-#{@site.publication_key}-#{@from.to_date}-#{@to.to_date}"
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

    @days = params[:days].to_i
    @days = 30 unless PERIODS.include?(@days)
    @to = Time.current
    @from = @days.days.ago.beginning_of_day
    @report = Analytics::Report.new(site: @site, from: @from, to: @to)
  end

  def csv_data
    CSV.generate(headers: true) do |csv|
      csv << ["pagina", "titulo", "visualizacoes", "visitantes_unicos"]
      @report.top_pages(limit: 1_000).each do |page|
        csv << [page[:path], page[:title], page[:views], page[:visitors]]
      end
    end
  end
end
