ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "action_dispatch/testing/integration"

class AnalyticsEventsTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @site = Site.create!(name: "Test publication", domain: "publication.example", publication_key: "reader-test", active: true)
    @session = ActionDispatch::Integration::Session.new(Rails.application)
    @session.host! "www.example.com"
    @params = { site: @site.publication_key, event_type: "click", session_id: "private-session",
      path: "/news?id=123&email=reader@example.com", title: "Example article", article_id: "123", author: "Ana",
      event_uuid: SecureRandom.uuid, page_view_uuid: SecureRandom.uuid, tracking_version: "2",
      client_occurred_at: 5.seconds.ago.iso8601(3), page_elapsed_ms: "12345", time_zone: "America/Sao_Paulo",
      utc_offset_minutes: "-180", scroll_depth: "75", active_seconds: "12", entry_path: "/entry?token=secret",
      previous_path: "/previous?email=secret", entry_referrer: "https://www.google.com/search?q=private",
      referrer: "https://www.google.com/search?q=private", target_url: "https://publication.example/next?token=secret#part",
      target_text: "Next article reader@example.com", click_placement: "related", link_type: "internal" }
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def request(params = @params, headers = {})
    Analytics::GeoLocation.stub(:call, { country_code: "BR", region: "Rio de Janeiro", city: "Rio de Janeiro", geo_source: "dbip_city_lite" }) do
      @session.post "/api/v1/analytics/events", params: params,
        headers: { "Origin" => "https://publication.example", "User-Agent" => "Mozilla/5.0 Chrome/130.0.0.0 Safari/537.36" }.merge(headers)
    end
  end

  def test_click_preserves_server_time_and_validated_reader_metadata_without_sensitive_urls
    request
    assert_equal 204, @session.response.status
    event = @site.analytics_events.last
    assert_in_delta Time.current.to_f, event.occurred_at.to_f, 3
    assert_in_delta 5, event.occurred_at - event.client_occurred_at, 3
    assert_equal 12345, event.page_elapsed_ms
    assert_equal "/news", event.path
    assert_equal "https://publication.example/next", event.target_url
    assert_equal "https://www.google.com", event.referrer
    assert_equal "BR", event.country_code
    assert_equal "related", event.metadata["click_placement"]
    assert_equal 75, event.metadata["scroll_depth"]
    assert_equal "Chrome", event.metadata["browser"]
    assert_equal "organic_search", event.metadata["traffic_channel"]
    assert_equal "/entry", event.metadata["entry_path"]
    assert_equal "/previous", event.metadata["previous_path"]
    assert_equal "America/Sao_Paulo", event.metadata["time_zone"]
    assert_equal event.occurred_at.in_time_zone("America/Sao_Paulo").hour, event.metadata["local_hour"]
    refute_includes event.target_text, "reader@example.com"
    refute_includes event.attributes.to_json, "private-session"
    refute_includes event.metadata.keys, "ip"
  end

  def test_duplicate_event_uuid_is_idempotent_per_publication
    2.times { request; assert_equal 204, @session.response.status }
    assert_equal 1, @site.analytics_events.count
    other = Site.create!(name: "Other", domain: "otherpublication.example", publication_key: "reader-other", active: true)
    request(@params.merge(site: other.publication_key), { "Origin" => "https://otherpublication.example" })
    assert_equal 204, @session.response.status
    assert_equal 1, other.analytics_events.count
  end

  def test_invalid_optional_values_and_spoofed_country_headers_are_not_trusted
    request(@params.merge(client_occurred_at: "1900-01-01T00:00:00Z", page_elapsed_ms: "-5", time_zone: "made/up",
      utc_offset_minutes: "9999", scroll_depth: "500", active_seconds: "-2", event_uuid: "bad", page_view_uuid: "bad",
      utm_source: "user@example.com", utm_campaign: "token=secret", click_placement: "#password", link_type: "secret"),
      { "CF-IPCountry" => "US", "CF-IPCity" => "Fake city" })
    assert_equal 204, @session.response.status
    event = @site.analytics_events.last
    assert_equal "BR", event.country_code
    assert_equal "Rio de Janeiro", event.metadata["city"]
    %w[time_zone local_hour scroll_depth active_seconds utm_source utm_campaign click_placement link_type].each do |key|
      refute event.metadata.key?(key), key
    end
    assert_nil event.client_occurred_at
    assert_nil event.page_elapsed_ms
    assert_nil event.event_uuid
  end

  def test_privacy_signals_bots_disallowed_origins_and_oversized_payloads_are_ignored
    [{ "DNT" => "1" }, { "Sec-GPC" => "1" }, { "User-Agent" => "ExampleCrawler" }].each do |headers|
      request(@params, headers)
      assert_equal 204, @session.response.status
    end
    request(@params, { "Origin" => "https://evil.example" })
    assert_equal 403, @session.response.status
    request(@params.merge(origin: "https://publication.example"), { "Origin" => "" })
    assert_equal 403, @session.response.status
    request(@params.merge(title: "x" * 20_000))
    assert_equal 413, @session.response.status
    assert_equal 0, @site.analytics_events.count
  end

  def test_legacy_events_and_missing_geo_database_continue_working_and_scroll_does_not_add_views
    legacy = @params.slice(:site, :event_type, :path, :title, :session_id)
    legacy[:event_type] = "page_view"
    request(legacy)
    assert_equal 204, @session.response.status
    assert_nil @site.analytics_events.last.client_occurred_at
    request(@params.merge(event_type: "scroll", value: "75"))
    assert_equal 204, @session.response.status
    assert_equal 1, @site.analytics_events.where(event_type: "page_view").count
    request(@params.merge(event_type: "unknown"))
    assert_equal 400, @session.response.status
  end
end
