require "openssl"
require "uri"

module Api
  module V1
    class AnalyticsEventsController < ActionController::API
      MAX_LENGTH = 500

      def create
        site = find_site!
        return head :forbidden unless allowed_origin?(site)
        return head :no_content if bot?

        site.analytics_events.create!(
          event_type: event_type,
          occurred_at: Time.current,
          path: clean(params[:path], 500).presence || "/",
          page_title: clean(params[:title], 250),
          content_key: clean(params[:article_id], 180),
          content_category: clean(params[:category], 120),
          content_author: clean(params[:author], 160),
          target_url: clean(params[:target_url], 500),
          target_text: clean(params[:target_text], 160),
          referrer: clean(params[:referrer], 500),
          session_hash: digest("session", params[:session_id].presence || request.request_id),
          visitor_hash: digest("visitor", [request.remote_ip, request.user_agent, Date.current.iso8601].join("|")),
          device_type: device_type,
          country_code: request.headers["CF-IPCountry"].to_s.first(2).presence,
          value: value
        )

        head :no_content
      rescue ActiveRecord::RecordNotFound
        head :not_found
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
        origin = request.headers["Origin"].presence || params[:origin].presence
        return false if origin.blank?

        host = URI.parse(origin).host.to_s.downcase.sub(/\Awww\./, "")
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
        AnalyticsEvent::EVENT_TYPES.include?(params[:event_type]) ? params[:event_type] : "page_view"
      end

      def value
        Integer(params[:value], exception: false).to_i.clamp(0, 86_400)
      end

      def clean(value, length = MAX_LENGTH)
        value.to_s.encode("UTF-8", invalid: :replace, undef: :replace).squish.first(length)
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
