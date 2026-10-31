require "uri"

module Analytics
  class ReaderMetadata
    UUID = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i
    PLACEMENTS = %w[header footer navigation article_body related homepage_lead homepage_grid share other].freeze

    def initialize(params:, request:, site:, received_at:)
      @params, @request, @site, @now = params, request, site, received_at
    end

    def call
      browser = Browser.new(@request.user_agent.to_s.first(1_000))
      geo = GeoLocation.call(@request.remote_ip)
      timezone = text(@params[:time_zone], 80)
      timezone = nil unless TZInfo::Timezone.all_identifiers.include?(timezone)
      offset = integer(:utc_offset_minutes, -840..840)
      local_time = if timezone
        @now.in_time_zone(timezone)
      elsif offset
        @now.getlocal(offset * 60)
      end
      client_time = parse_client_time
      referrer = self.class.url(@params[:referrer], origin_only: true)
      utm = %i[utm_source utm_medium utm_campaign].to_h { |key| [key, campaign(@params[key])] }.compact
      entry_referrer = self.class.url(@params[:entry_referrer], origin_only: true)
      source, channel = traffic(@params[:tracking_version].to_s == "2" ? entry_referrer : referrer, utm)
      meta = { tracking_version: @params[:tracking_version].to_s == "2" ? 2 : 1,
        time_zone: timezone, utc_offset_minutes: offset, local_hour: local_time&.hour,
        clock_skew_ms: client_time && ((client_time - @now) * 1000).round,
        scroll_depth: integer(:scroll_depth, 0..100), active_seconds: integer(:active_seconds, 0..86_400),
        browser: browser.name.first(40), operating_system: browser.platform.name.first(40),
        traffic_source: source, traffic_channel: channel,
        entry_path: self.class.path(@params[:entry_path]), previous_path: self.class.path(@params[:previous_path]),
        click_placement: PLACEMENTS.include?(@params[:click_placement]) ? @params[:click_placement] : nil,
        link_type: %w[internal external action share].include?(@params[:link_type]) ? @params[:link_type] : nil,
        language: @params[:language].to_s.match?(/\A[a-z]{2}\z/i) ? @params[:language].downcase : nil,
        region: geo[:region], city: geo[:city], geo_source: geo[:geo_source] }.merge(utm).compact
      { metadata: meta, country_code: geo[:country_code], client_occurred_at: client_time,
        page_elapsed_ms: integer(:page_elapsed_ms, 0..86_400_000),
        event_uuid: uuid(:event_uuid), page_view_uuid: uuid(:page_view_uuid) }
    end

    def self.url(value, origin_only: false)
      uri = URI.parse(value.to_s.first(2_000))
      return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      return if sensitive_path?(uri.path)
      uri.query = uri.fragment = nil
      uri.path = "" if origin_only
      uri.to_s.first(500)
    rescue URI::InvalidURIError
      nil
    end

    def self.path(value)
      string = value.to_s.first(2_000)
      return unless string.start_with?("/") && !string.start_with?("//") && !string.match?(/[\x00-\x20\\]/)
      path = URI.parse(string).path
      path.presence&.first(500) unless sensitive_path?(path)
    rescue URI::InvalidURIError
      nil
    end

    def self.text(value, length)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace).gsub(/[\u0000-\u001f\u007f]/, " ")
        .gsub(/[\w.+-]+@[\w.-]+\.[a-z]{2,}/i, "[redacted]")
        .gsub(/\+?\d[\d ()-]{6,}\d/, "[redacted]").squish.first(length).presence
    end

    def self.sensitive_path?(value)
      decoded = URI::DEFAULT_PARSER.unescape(value.to_s)
      decoded.match?(%r{@|\d{9,}|/(?:reset-password|password|token|unsubscribe|login)(?:/|$)}i)
    end

    private

    def text(value, length)
      self.class.text(value, length)
    end

    def uuid(key)
      value = @params[key].to_s
      value if value.match?(UUID)
    end

    def integer(key, range)
      value = Integer(@params[key].to_s, exception: false)
      value if value && range.cover?(value)
    end

    def parse_client_time
      value = Time.iso8601(@params[:client_occurred_at].to_s)
      value if (value - @now).abs <= 7.days
    rescue ArgumentError
      nil
    end

    def campaign(value)
      value = value.to_s.first(100)
      value if value.present? && value.match?(/\A[a-zA-Z0-9 _.-]{1,80}\z/) && !value.match?(/\d{7,}/)
    end

    def traffic(referrer, utm)
      medium = utm[:utm_medium].to_s.downcase
      if utm.any?
        channel = if %w[email newsletter].include?(medium) then "email"
        elsif %w[cpc ppc paid paid_social display].include?(medium) then "paid"
        elsif %w[social organic_social].include?(medium) then "organic_social"
        else "campaign"
        end
        return [utm[:utm_source] || "campaign", channel]
      end
      host = URI.parse(referrer.to_s).host.to_s.downcase.delete_prefix("www.")
      return ["direct", "direct_or_unknown"] if host.empty?
      return [host, "internal"] if host == @site.domain.to_s.delete_prefix("www.")
      search = %w[google.com google.com.br bing.com duckduckgo.com search.yahoo.com]
      social = %w[facebook.com instagram.com t.co twitter.com x.com linkedin.com whatsapp.com wa.me youtube.com]
      channel = if search.any? { |domain| host == domain || host.end_with?(".#{domain}") } then "organic_search"
      elsif social.any? { |domain| host == domain || host.end_with?(".#{domain}") } then "organic_social"
      else "referral"
      end
      [host.first(120), channel]
    end
  end
end
