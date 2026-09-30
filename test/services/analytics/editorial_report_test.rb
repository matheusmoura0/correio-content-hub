# Run against a dedicated test database:
# RAILS_ENV=test bundle exec ruby test/services/analytics/editorial_report_test.rb
ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"

class EditorialReportTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    token = SecureRandom.hex(8)
    @site = Site.create!(name: "Editorial test", domain: "#{token}.example", publication_key: token,
      site_type: "editorial", content_mode: "hub", layout_profile: "standard", active: true)
    @from = Time.utc(2026, 9, 10)
    @to = Time.utc(2026, 9, 17)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def event(key: "a", author: "Ana", category: "Cinema", type: "page_view", at: @from, value: 0, title: "Cinema", site: @site)
    site.analytics_events.create!(content_key: key, content_author: author, content_category: category,
      event_type: type, occurred_at: at, value: value, page_title: title, path: "/#{key}",
      visitor_hash: "visitor", session_hash: "session", device_type: "desktop")
  end

  def report(**options)
    Analytics::EditorialReport.new(site: @site, from: @from, to: @to, **options)
  end

  def test_period_boundary_and_previous_window
    event(at: @from - 1)
    event(at: @from)
    event(at: @to - 1)
    event(at: @to)
    assert_equal 2, report.summary[:views]
    assert_equal 1, report.summary(previous: true)[:views]
    assert_equal 100.0, report.rows.first[:views_change]
    assert_equal 7, report.daily_views.size
  end

  def test_author_totals_and_median_do_not_count_clicks_as_views
    3.times { event }
    event(key: "b")
    event(type: "click")
    event(type: "engagement", value: 30)
    row = report(dimension: "authors").rows.first
    assert_equal 4, row[:views]
    assert_equal 2, row[:articles]
    assert_equal 2.0, row[:median_views]
    assert_equal 1, row[:clicks]
    assert_equal 30, row[:engagement_seconds]
    assert_nil row[:views_change]
  end

  def test_missing_metadata_and_unidentified_pages
    event(author: nil, category: nil)
    event(key: nil)
    row = report(dimension: "authors").rows.first
    assert_equal "Não informado", row[:name]
    assert_equal 1, report(filters: { author: "__missing__" }).summary[:views]
    assert_equal 1, report.summary[:articles]
  end

  def test_filters_are_applied_to_both_periods_and_exports
    event(author: "Ana", category: "Cinema")
    event(author: "Ana", category: "Cinema", at: @from - 1)
    event(author: "Bia", category: "Política")
    result = report(filters: { author: "Ana", category: "Cinema" })
    assert_equal 1, result.summary[:views]
    assert_equal 1, result.summary(previous: true)[:views]
    assert_equal 1, result.as_json[:rows].length
    assert_equal "Ana", result.as_json[:filters][:author]
  end

  def test_search_treats_wildcards_as_literal_and_handles_quotes
    event(title: "100% cinema")
    event(key: "b", title: "Outra notícia")
    assert_equal 1, report(filters: { q: "100%" }).summary[:views]
    assert_equal 0, report(filters: { q: "' OR 1=1 --" }).summary[:views]
  end

  def test_site_isolation_and_empty_summary
    other = @site.dup
    other.domain = "other.example"
    other.publication_key = "other-test"
    other.save!
    event(site: other)
    assert_equal 0, report.summary[:views]
    assert_equal [], report.rows
    assert_nil report.comparison[:views]
  end

  def test_pagination_is_stable_and_export_is_not_paginated
    %w[a b c].each { |key| event(key: key) }
    assert_equal ["b"], report.rows(limit: 1, offset: 1).map { |row| row[:key] }
    assert_equal 3, report.total_rows
    assert_equal 3, report.as_json[:rows].length
  end

  def test_sort_and_dimension_allowlists
    event
    result = report(dimension: "anything", sort: "views; DROP TABLE sites")
    assert_equal "articles", result.dimension
    assert_equal "views", result.sort
    assert_equal 1, result.rows.size
  end
  def test_csv_cells_do_not_execute_spreadsheet_formulas
    controller = AnalyticsController.new
    assert_equal "'=SUM(A1:A2)", controller.send(:csv_cell, "=SUM(A1:A2)")
    assert_equal "'  +123", controller.send(:csv_cell, "  +123")
    assert_equal "Cinema", controller.send(:csv_cell, "Cinema")
    assert_equal(-25.0, controller.send(:csv_cell, -25.0))
  end

end
