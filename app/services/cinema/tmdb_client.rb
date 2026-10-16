require "net/http"
require "json"

module Cinema
  class TmdbClient
    BASE_URL = "https://api.themoviedb.org/3"
    CACHE_TTL = 20.minutes

    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    def initialize(token: ENV["TMDB_API_TOKEN"])
      @token = token.to_s
      raise ConfigurationError, "TMDB_API_TOKEN não configurado" if @token.blank?
    end

    def home
      Rails.cache.fetch("tmdb/home/pt-BR/BR", expires_in: CACHE_TTL) do
        {
          trending: get("/trending/all/day"),
          now_playing: get("/movie/now_playing", region: "BR"),
          upcoming: get("/movie/upcoming", region: "BR"),
          top_rated: get("/movie/top_rated", region: "BR"),
          streaming: get("/discover/movie", watch_region: "BR", with_watch_monetization_types: "flatrate", sort_by: "popularity.desc"),
          attribution: attribution
        }
      end
    end

    def movie(id)
      Rails.cache.fetch("tmdb/movie/#{Integer(id)}/pt-BR/BR", expires_in: CACHE_TTL) do
        data = get("/movie/#{Integer(id)}", append_to_response: "videos,watch/providers,credits,recommendations")
        data.merge("attribution" => attribution)
      end
    end

    def tv(id)
      Rails.cache.fetch("tmdb/tv/#{Integer(id)}/pt-BR/BR", expires_in: CACHE_TTL) do
        data = get("/tv/#{Integer(id)}", append_to_response: "videos,watch/providers,credits,recommendations")
        data.merge("attribution" => attribution)
      end
    end

    private

    def get(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form({ language: "pt-BR" }.merge(params))
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 12) do |http|
        http.request(request)
      end
      raise RequestError, "TMDB respondeu com HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise RequestError, "TMDB retornou uma resposta inválida"
    end

    def attribution
      {
        tmdb: "This product uses the TMDB API but is not endorsed or certified by TMDB.",
        streaming: "Disponibilidade de streaming fornecida por JustWatch via TMDB.",
        image_base_url: "https://image.tmdb.org/t/p/"
      }
    end
  end
end
