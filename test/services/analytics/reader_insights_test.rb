ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"

class ReaderInsightsTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @site = Site.create!(name: "Audience", domain: "audience.example", publication_key: "audience", active: true)
    @from, @to = Time.utc(2026, 10, 26), Time.utc(2026, 10, 28)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def event(reader, type: "page_view", metadata: {}, site: @site, at: Time.utc(2026, 10, 27, 15), page: nil, author: "Ana")
    site.analytics_events.create!(event_type: type, occurred_at: at, path: "/story", content_key: "story",
      content_author: author, visitor_hash: "private-reader-#{reader}", session_hash: "private-session-#{reader}",
      page_view_uuid: page, device_type: "mobile", country_code: "BR", page_elapsed_ms: 10000, value: type == "engagement" ? 10 : 0,
      metadata: { tracking_version: 2, city: "Rio", region: "RJ", geo_source: "dbip_city_lite", browser: "Chrome",
        operating_system: "Android", traffic_source: "google.com", traffic_channel: "organic_search", time_zone: "America/Sao_Paulo",
        click_placement: "related", active_seconds: 0, scroll_depth: 0 }.merge(metadata))
  end

  def report(**options)
    Analytics::EditorialReport.new(site: @site, from: @from, to: @to, **options)
  end

  def test_coverage_hourly_counts_and_reading_use_the_right_denominators
    6.times do |i|
      page = SecureRandom.uuid
      event(i, page: page)
      event(i, page: page, type: "engagement", metadata: { active_seconds: 10, scroll_depth: 50 })
      event(i, page: page, type: "engagement", metadata: { active_seconds: 20, scroll_depth: 75 })
      event(i, page: page, type: "click", metadata: { active_seconds: 20, scroll_depth: 75 })
    end
    legacy = event("legacy")
    legacy.update!(metadata: {})
    insight = report.reader_insights
    assert_equal 7, insight.coverage[:total]
    assert_equal 6, insight.coverage[:known]
    assert_equal 6, insight.coverage[:clicks]
    assert_equal 85.7, insight.coverage[:percent]
    assert_equal [{ label: "Rio · RJ · BR", count: 6 }], insight.breakdowns[:cities]
    assert_equal [{ label: "google.com · Busca orgânica", count: 6 }], insight.breakdowns[:sources]
    assert_equal 6, insight.hourly[12][:views]
    assert_equal 6, insight.hourly[12][:clicks]
    assert_equal 0, insight.hourly[11][:views]
    assert_equal 6, insight.reading[:pages]
    assert_equal 20, insight.reading[:active_seconds], "Cumulative activity must not be summed across events"
    assert_equal 100.0, insight.reading[:scroll_75_percent]
    assert_equal 10.0, insight.reading[:click_delay_seconds]
    refute_includes insight.breakdowns.to_json, "private-reader"
  end

  def test_repeated_events_from_one_identifier_cannot_reveal_small_groups
    20.times { event("one", type: "click", metadata: { city: "PrivateTown", click_placement: "footer" }) }
    20.times { event("one", metadata: { city: "PrivateTown", browser: "PrivateBrowser" }) }
    insight = report.reader_insights
    assert_equal [], insight.breakdowns[:cities]
    assert_equal [], insight.breakdowns[:browsers]
    assert_equal [], insight.breakdowns[:placements]
    assert_nil insight.hourly[12][:clicks]
    assert_nil insight.hourly[12][:views]
    assert_nil insight.reading[:active_seconds]
    assert_nil insight.reading[:click_delay_seconds]
    refute_includes insight.breakdowns.to_json, "PrivateTown"
  end

  def test_site_period_and_editorial_filters_are_preserved
    other = Site.create!(name: "Other", domain: "other.example", publication_key: "other-insights", active: true)
    6.times do |i|
      event(i)
      event("other-#{i}", site: other, metadata: { city: "Other site secret" })
      event("future-#{i}", at: @to, metadata: { city: "Outside period" })
      event("bia-#{i}", author: "Bia", metadata: { city: "Other author" })
    end
    insight = report(filters: { author: "Ana" }).reader_insights
    assert_equal 6, insight.coverage[:known]
    assert_equal [{ label: "Rio · RJ · BR", count: 6 }], insight.breakdowns[:cities]
    assert_equal 0, report(filters: { q: "does-not-exist" }).reader_insights.coverage[:known]
  end

  def test_legacy_only_data_is_not_fabricated_and_malformed_numbers_are_safe
    6.times { |i| event(i).update!(metadata: {}) }
    insight = report.reader_insights
    assert_equal 0, insight.coverage[:known]
    assert_equal 6, insight.coverage[:total]
    assert_equal [], insight.breakdowns[:countries]
    assert_equal 0, insight.reading[:pages]
    assert_nil insight.reading[:scroll_75_percent]
    6.times { |i| event(i, page: SecureRandom.uuid, metadata: { active_seconds: "invalid", scroll_depth: "bad" }) }
    assert_nil report.reader_insights.reading[:active_seconds]
  end
end
