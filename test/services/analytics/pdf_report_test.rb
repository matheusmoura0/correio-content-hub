ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"

class AnalyticsPdfReportTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @site = Site.create!(name: "Correio da Manhã", domain: "correiodamanha.com.br", publication_key: "correio-da-manha", active: true)
    @from = Time.utc(2026, 10, 1)
    @to = Time.utc(2026, 10, 8)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def event(index, title: "Matéria #{index}: inovação e educação", author: "João Repórter")
    @site.analytics_events.create!(content_key: index.to_s, content_author: author, content_category: "Educação",
      event_type: "page_view", occurred_at: @from + 1.hour, page_title: title, path: "/materia",
      visitor_hash: "private-visitor", session_hash: "private-session", device_type: "mobile", value: 0)
  end

  def generate(**options)
    report = Analytics::EditorialReport.new(site: @site, from: @from, to: @to, **options)
    generator = Analytics::PdfReport.new(report)
    bytes = generator.call
    assert bytes.start_with?("%PDF-")
    text = IO.popen(["pdftotext", "-layout", "-", "-"], "r+") { |io| io.write(bytes); io.close_write; io.read }
    assert $?.success?, "Invalid PDF"
    [generator, text]
  end

  def test_empty_report_has_brand_period_notes_and_no_division_by_zero
    _, text = generate
    assert_includes text, "Correio da Manhã"
    assert_includes text, "01/10/2026 a 07/10/2026"
    assert_includes text, "Nenhum resultado"
    assert_includes text, "Notas de medição"
    assert_includes text, "Sem base"
  end

  def test_all_rows_are_exported_with_repeated_headers_and_accented_names
    30.times { |i| event(i) }
    generator, text = generate
    assert_operator generator.instance_variable_get(:@pdf).page_count, :>, 2
    30.times { |i| assert_includes text, "Matéria #{i}:" }
    assert_operator text.scan("Ranking").length, :>=, 2
    assert_equal generator.instance_variable_get(:@pdf).page_count, text.scan("RELATÓRIO DE AUDIÊNCIA").length
    assert_includes text, "CM"
    assert_includes text, "João Repórter"
    refute_includes text, "private-visitor"
    refute_includes text, "private-session"
  end

  def test_author_and_category_reports_preserve_filters_and_dimension
    event(1)
    event(2, author: "Outra pessoa")
    _, authors = generate(dimension: "authors", filters: { author: "João Repórter" })
    assert_includes authors, "Jornalistas"
    assert_includes authors, "Assinatura: João Repórter"
    refute_includes authors, "Outra pessoa"
    _, categories = generate(dimension: "categories")
    assert_includes categories, "Editorias"
    assert_includes categories, "Educação"
  end

  def test_long_titles_and_markup_are_safe_and_notes_are_not_lost
    event(1, title: "<b>Notícia & análise</b> " + "Título longo " * 150)
    _, text = generate(filters: { q: "Notícia" })
    assert_includes text, "<b>Notícia & análise</b>"
    assert_includes text, "Notas de medição"
    assert_includes text, "ranking inclui todos os resultados"
  end
end
