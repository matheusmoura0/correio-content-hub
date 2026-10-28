require "openssl"
require "uri"

module Api
  module V1
    class AnalyticsEventsController < ActionController::API
      MAX_LENGTH = 500

      def create
        return head :content_too_large if request.content_length.to_i > 16_384
        return head :no_content if request.headers["Sec-GPC"] == "1" || request.headers["DNT"] == "1"
        site = find_site!
        return head :forbidden unless allowed_origin?(site)
        return head :no_content if bot?
        return head :bad_request unless AnalyticsEvent::EVENT_TYPES.include?(event_type)
        now = Time.current
        enrichment = Analytics::ReaderMetadata.new(params: params, request: request, site: site, received_at: now).call

        site.analytics_events.create!(
          event_type: event_type,
          occurred_at: now,
          path: Analytics::ReaderMetadata.path(params[:path]) || "/",
          page_title: clean(params[:title], 250),
          content_key: clean(params[:article_id], 180),
          content_category: clean(params[:category], 120),
          content_author: clean(params[:author], 160),
          image_url: Analytics::ReaderMetadata.url(params[:image_url]),
          author_image_url: Analytics::ReaderMetadata.url(params[:author_image_url]),
          target_url: Analytics::ReaderMetadata.url(params[:target_url]),
          target_text: Analytics::ReaderMetadata.text(params[:target_text], 100),
          referrer: Analytics::ReaderMetadata.url(params[:referrer], origin_only: true),
          session_hash: digest("session", params[:session_id].presence || request.request_id),
          visitor_hash: digest("visitor", [request.remote_ip, request.user_agent, now.utc.to_date.iso8601].join("|")),
          device_type: device_type,
          value: value,
          **enrichment
        )

        head :no_content
      rescue ActiveRecord::RecordNotFound
        head :not_found
      rescue ActiveRecord::RecordNotUnique
        head :no_content
      rescue ActiveRecord::RecordInvalid => error
        Rails.logger.warn("Evento analítico rejeitado: #{error.record.errors.full_messages.to_sentence}")
        head :unprocessable_entity
      end

      private

      def find_site!
        key = params[:site].to_s
        Site.where(active: true).find_by!(publication_key: key)
      end

      def allowed_origin?(site)
        origin = request.headers["Origin"].presence
        return false if origin.blank?
        uri = URI.parse(origin)
        return false unless uri.is_a?(URI::HTTP) && uri.userinfo.nil? && [80, 443].include?(uri.port)
        host = uri.host.to_s.downcase.sub(/\Awww\./, "")
        allowed_hosts = site.allowed_origin_list.filter_map do |allowed|
          URI.parse(allowed).host.to_s.downcase.sub(/\Awww\./, "").presence
        rescue URI::InvalidURIError
          nil
        end
        allowed_hosts << site.domain.to_s.downcase.sub(/\Awww\./, "")
        allowed_hosts.include?(host)
      rescue URI::InvalidURIError
        false
      end

      def event_type
        params[:event_type].presence || "page_view"
      end

      def value
        Integer(params[:value], exception: false).to_i.clamp(0, 86_400)
      end

      def clean(value, length = MAX_LENGTH)
        value.to_s.encode("UTF-8", invalid: :replace, undef: :replace).gsub(/[\u0000-\u001f\u007f]/, " ").squish.first(length)
      end

      def digest(namespace, value)
        OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{namespace}|#{value}")
      end

      def bot?
        request.user_agent.to_s.match?(/bot|crawler|spider|preview|headless/i)
      end

      def device_type
        agent = request.user_agent.to_s
        return "tablet" if agent.match?(/ipad|tablet/i)
        return "mobile" if agent.match?(/mobile|iphone|android/i)

        "desktop"
      end
    end
  end
end
