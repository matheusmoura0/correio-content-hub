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

  def event(index, title: "Matéria #{index}: inovação e educação", author: "João Repórter", type: "page_view", value: 0, previous: false)
    @site.analytics_events.create!(content_key: index.to_s, content_author: author, content_category: "Educação",
      event_type: type, occurred_at: @from + (previous ? -1.hour : 1.hour), page_title: title, path: "/materia",
      visitor_hash: "private-visitor", session_hash: "private-session", device_type: "mobile", value: value)
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

  def test_only_top_ten_are_exported_with_complete_summary_and_repeated_branding
    30.times { |i| (i + 1).times { event(i) } }
    generator, text = generate
    assert_operator generator.instance_variable_get(:@pdf).page_count, :<=, 3
    assert_equal (20...30).to_a.reverse.map(&:to_s), generator.instance_variable_get(:@rows).map { |row| row[:key] }
    (20...30).each { |i| assert_includes text, "Matéria #{i}:" }
    refute_includes text, "Matéria 19:"
    assert_includes text, "Top 10 de 30 resultados"
    assert_includes text, "465"
    assert_includes text, "Destaques de audiência"
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
    assert_includes text.gsub(/\s+/, " "), "ranking completo permanece no painel"
    assert_includes text, "180 caracteres"
  end

  def test_selected_metric_controls_order_values_and_previous_period_comparison
    event(1, author: "Ana")
    3.times { event(2, author: "Bia") }
    4.times { event(1, author: "Ana", type: "click") }
    2.times { event(1, author: "Ana", type: "click", previous: true) }
    event(2, author: "Bia", type: "engagement", value: 180)
    event(2, author: "Bia", type: "engagement", value: 60, previous: true)

    clicks, text = generate(dimension: "authors", sort: "clicks")
    first = clicks.instance_variable_get(:@rows).first
    assert_equal "Ana", first[:name]
    assert_equal 4, first[:clicks]
    assert_equal 2, first[:previous_clicks]
    assert_includes text, "+100.0%"
    assert_includes text, "ordem por cliques"

    time, text = generate(dimension: "authors", sort: "engagement_seconds")
    assert_equal "Bia", time.instance_variable_get(:@rows).first[:name]
    assert_includes text, "0h 3min 0s"
    assert_includes text, "0h 1min 0s"
    assert_includes text, "+200.0%"

    articles, text = generate(dimension: "authors", sort: "articles")
    assert_equal 1, articles.instance_variable_get(:@rows).first[:articles]
    assert_includes text, "ordem por conteúdos acessados"
  end
end
