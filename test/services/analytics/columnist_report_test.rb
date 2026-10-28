ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"

class ColumnistReportTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @site = Site.create!(name: "Correio da Manhã", domain: "correiodamanha.com.br", publication_key: "correio-da-manha", active: true)
    @from = Time.utc(2026, 10, 1)
    @to = Time.utc(2026, 10, 8)
    @paulo = profile("paulo-cappelli", "Paulo Cappelli")
    @william = profile("brasilianas", "William França")
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def profile(slug, name, **attributes)
    @site.analytics_author_profiles.create!(slug: slug, name: name,
      source_url: "https://www.correiodamanha.com.br/colunistas/#{slug}",
      image_url: "https://www.correiodamanha.com.br/images/cm/colunistas/#{slug}.jpg", **attributes)
  end

  def event(key, author, at: @from, category: "Paulo Cappelli", site: @site)
    site.analytics_events.create!(content_key: key, content_author: author, content_category: category,
      event_type: "page_view", occurred_at: at, page_title: "Matéria #{key}", path: "/colunistas/paulo-cappelli/#{key}",
      visitor_hash: "visitor", session_hash: "session", device_type: "mobile", value: 0)
  end

  def report(**options)
    Analytics::EditorialReport.new(site: @site, from: @from, to: @to, dimension: "columnists", **options)
  end

  def test_only_individual_bylines_are_grouped_without_assigning_other_reporters
    event("a", "Paulo Cappelli")
    2.times { event("b", "  POR   PAULO CAPPELLI ") }
    event("shared", "Paulo Cappelli e Lucas Gayoso")
    event("reporter", "Lucas Gayoso - BSB")
    event("missing", nil)
    event("william", "por William Franca", category: "Brasilianas")
    profile("correio-bastidores", "Correio Bastidores", individual: false)
    event("collective", "Correio Bastidores")
    event("previous", "por Paulo Cappelli", at: @from - 1.hour)
    result = report
    assert_equal 2, result.total_rows
    assert_equal 4, result.summary[:views]
    paulo = result.rows.first
    assert_equal "paulo-cappelli", paulo[:key]
    assert_equal "Paulo Cappelli", paulo[:name]
    assert_equal 3, paulo[:views]
    assert_equal 2, paulo[:articles]
    assert_equal 1, paulo[:previous_views]
    assert_equal 200.0, paulo[:views_change]
    assert_equal 1.5, paulo[:median_views]
    assert_equal @paulo.image_url, paulo[:author_image_url]
    assert_equal 8, @site.analytics_events.where(occurred_at: @from...@to).count
    authors = Analytics::EditorialReport.new(site: @site, from: @from, to: @to, dimension: "authors").rows
    assert_includes authors.map { |row| row[:name] }, "Paulo Cappelli e Lucas Gayoso"
    assert_includes authors.map { |row| row[:name] }, "Lucas Gayoso - BSB"
  end

  def test_drilldown_periods_search_and_images_use_the_same_identity
    event("a", "Paulo Cappelli")
    event("b", "POR Paulo Cappelli")
    event("other", "Lucas Gayoso - BSB")
    result = Analytics::EditorialReport.new(site: @site, from: @from, to: @to, filters: { columnist: @paulo.slug })
    assert_equal %w[a b], result.rows.map { |row| row[:key] }
    assert_equal 2, result.summary[:views]
    assert_equal "Paulo Cappelli", result.columnist_name
    assert_includes result.notes.join, "coautorias"
    assert_equal [@paulo.image_url], result.rows.map { |row| row[:author_image_url] }.uniq
    magnavita = profile("magnavita", "Cláudio Magnavita", aliases: ["Magnavita"])
    event("m", "Magnavita")
    assert_equal [magnavita.slug], report(filters: { q: "Claudio Magnavita" }).rows.map { |row| row[:key] }
    assert_equal 0, report(filters: { columnist: "' OR 1=1 --" }).summary[:views]
  end

  def test_profiles_are_site_scoped_and_unknown_bylines_are_not_guessed
    other = Site.create!(name: "Correio da Manhã", domain: "other.example", publication_key: "other", active: true)
    other.analytics_author_profiles.create!(slug: "foreign", name: "Outra pessoa", source_url: "https://www.correiodamanha.com.br/colunistas/foreign")
    event("a", "Outra pessoa")
    event("b", "Paulo Cappelli", site: other)
    event("c", "Paulo Cappelli Jr.")
    event("d", "William França e outra pessoa")
    assert_equal [], report.rows
    assert_equal 0, report.summary[:views]
    @paulo.update!(active: false)
    event("e", "Paulo Cappelli")
    assert_equal [], report.rows
  end

  def test_aliases_are_normalized_unique_and_quoted_safely
    assert_equal "william franca", Analytics::AuthorIdentity.normalize(" POR   WILLIAM FRANÇA ")
    duplicate = @site.analytics_author_profiles.new(slug: "duplicate", name: "POR PAULO CAPPELLI", source_url: "https://www.correiodamanha.com.br/colunistas/duplicate")
    refute duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :aliases
    quoted = profile("davila", "João D'Ávila")
    event("quoted", "por João D'Ávila")
    assert_equal [quoted.slug], report.rows.map { |row| row[:key] }
    @william.image_url = "https://evil.example/someone.jpg"
    refute @william.valid?
    @william.image_url = "https://www.correiodamanha.com.br/images/logo_600x450.jpg"
    refute @william.valid?
  end
end
