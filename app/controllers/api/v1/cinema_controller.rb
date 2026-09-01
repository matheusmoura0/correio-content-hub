module Api
  module V1
    class CinemaController < ActionController::API
      after_action :disable_cache

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
    end
  end
end
