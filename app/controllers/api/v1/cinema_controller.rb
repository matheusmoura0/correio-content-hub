module Api
  module V1
    class CinemaController < ActionController::API
      after_action :disable_cache
      after_action :allow_publication_sites

      def home
        render json: Cinema::TmdbClient.new.home
      rescue Cinema::TmdbClient::ConfigurationError => error
        render json: { error: error.message }, status: :service_unavailable
      rescue Cinema::TmdbClient::RequestError => error
        render json: { error: error.message }, status: :bad_gateway
      end

      def movie
        render json: Cinema::TmdbClient.new.movie(params[:id])
      rescue ArgumentError
        render json: { error: "Identificador de filme inválido" }, status: :unprocessable_entity
      rescue Cinema::TmdbClient::ConfigurationError => error
        render json: { error: error.message }, status: :service_unavailable
      rescue Cinema::TmdbClient::RequestError => error
        render json: { error: error.message }, status: :bad_gateway
      end

      def tv
        render json: Cinema::TmdbClient.new.tv(params[:id])
      rescue ArgumentError
        render json: { error: "Identificador de série inválido" }, status: :unprocessable_entity
      rescue Cinema::TmdbClient::ConfigurationError => error
        render json: { error: error.message }, status: :service_unavailable
      rescue Cinema::TmdbClient::RequestError => error
        render json: { error: error.message }, status: :bad_gateway
      end

      private

      def disable_cache
        response.set_header("Cache-Control", "public, max-age=60, s-maxage=600, stale-while-revalidate=3600")
      end

      def allow_publication_sites
        allowed = Site.where(active: true).pluck(:allowed_origins).flat_map do |origins|
          origins.to_s.lines.map(&:strip)
        end.reject(&:blank?).uniq
        origin = request.headers["Origin"]
        response.set_header("Access-Control-Allow-Origin", origin) if allowed.include?(origin)
        response.set_header("Vary", "Origin")
      end
    end
  end
end
