ENV["RAILS_ENV"] = "test"
require_relative "../../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class ReaderMetadataTest < Minitest::Test
  def test_urls_paths_and_free_text_are_sanitized
    helper = Analytics::ReaderMetadata
    assert_equal "https://example.com/story", helper.url("https://example.com/story?token=secret#private")
    assert_equal "https://example.com", helper.url("https://example.com/search?q=private", origin_only: true)
    ["javascript:alert(1)", "mailto:private@example.com", "https://user:password@example.com/story", "https://example.com/reset-password/secret"].each { |url| assert_nil helper.url(url) }
    assert_nil helper.path("//evil.example/path")
    assert_nil helper.path("/users/private%40example.com")
    assert_equal "/story", helper.path("/story?email=private#part")
    assert_equal "Contact [redacted] [redacted]", helper.text("Contact reader@example.com +5511999999999\u0000", 100)
  end

  def test_geo_missing_or_private_addresses_fail_closed
    %w[127.0.0.1 ::1 192.168.1.1 169.254.169.254 nonsense].each do |ip|
      assert_equal({}, Analytics::GeoLocation.call(ip))
    end
    Analytics::GeoLocation.stub(:path, Pathname.new("/nonexistent/geoip.mmdb")) do
      assert_equal({}, Analytics::GeoLocation.call("8.8.8.8"))
    end
  end

  def test_local_hour_uses_server_time_not_a_skewed_device_clock_and_sources_are_classified
    now = Time.utc(2026, 10, 28, 2, 30)
    site = Struct.new(:domain).new("publication.example")
    req = Struct.new(:user_agent, :remote_ip).new("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1", "127.0.0.1")
    params = { client_occurred_at: (now + 2.days).iso8601, time_zone: "America/Sao_Paulo", utm_source: "newsletter", utm_medium: "email", utm_campaign: "morning-edition" }
    result = Analytics::ReaderMetadata.new(params: params, request: req, site: site, received_at: now).call
    assert_equal 23, result[:metadata][:local_hour]
    assert_equal "email", result[:metadata][:traffic_channel]
    assert_equal "newsletter", result[:metadata][:traffic_source]
    assert_equal 2.days * 1000, result[:metadata][:clock_skew_ms]
    assert_equal "Safari", result[:metadata][:browser]
    assert_equal "iOS", result[:metadata][:operating_system]
  end

  def test_retention_clears_only_enrichment_and_preserves_historical_counts
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    site = Site.create!(name: "Retention", domain: "retention.example", publication_key: "retention", active: true)
    base = { path: "/story", content_key: "one", event_type: "page_view", occurred_at: 91.days.ago,
      session_hash: "session", visitor_hash: "visitor", device_type: "mobile", value: 0 }
    old = site.analytics_events.create!(**base, metadata: { city: "City", tracking_version: 2 }, country_code: "BR", page_elapsed_ms: 200)
    fresh = site.analytics_events.create!(**base.merge(occurred_at: 1.day.ago), metadata: { city: "City" })
    legacy = site.analytics_events.create!(**base, country_code: "US")
    Analytics::PruneReaderMetadata.call
    assert_equal({}, old.reload.metadata)
    assert_nil old.country_code
    assert_nil old.page_elapsed_ms
    assert_equal "City", fresh.reload.metadata["city"]
    assert_equal "US", legacy.reload.country_code
    assert_equal 3, site.analytics_events.count
  ensure
    ActiveRecord::Base.connection.rollback_transaction
  end
end
