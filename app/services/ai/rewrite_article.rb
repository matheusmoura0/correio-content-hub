require "net/http"
require "json"

module Ai
  class RewriteArticle
    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    ENDPOINT = URI("https://models.github.ai/inference/chat/completions")

    def self.call(article, instructions: nil)
      new(article, instructions:).call
    end

    def initialize(article, instructions: nil)
      @article = article
      @instructions = instructions.presence || "Mantenha um tom jornalístico, claro, objetivo e neutro."
    end

    def call
      token = ENV["GITHUB_MODELS_TOKEN"]
      raise ConfigurationError, "Configure GITHUB_MODELS_TOKEN no servidor." if token.blank?

      response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, read_timeout: 90, open_timeout: 10) do |http|
        http.request(request(token))
      end
      raise RequestError, "A IA respondeu com HTTP #{response.code}." unless response.is_a?(Net::HTTPSuccess)

      parse_content(response.body)
    rescue JSON::ParserError
      raise RequestError, "A IA retornou uma resposta inválida."
    end

    private

    def request(token)
      Net::HTTP::Post.new(ENDPOINT).tap do |request|
        request["Authorization"] = "Bearer #{token}"
        request["Content-Type"] = "application/json"
        request.body = {
          model: ENV.fetch("GITHUB_MODELS_MODEL", "openai/gpt-4.1-mini"),
          temperature: 0.4,
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: source_text }
          ]
        }.to_json
      end
    end

    def system_prompt
      <<~PROMPT
        Você é um editor jornalístico brasileiro. Reescreva a matéria com texto original, preservando somente os fatos presentes na fonte. Não invente informações, declarações ou contexto. Não copie frases extensas. #{ @instructions }
        Responda apenas em JSON válido no formato {"title":"...","content":"..."}. O conteúdo deve usar parágrafos separados por duas quebras de linha.
      PROMPT
    end

    def source_text
      body = @article.content.presence || @article.description
      cleaned = ActionView::Base.full_sanitizer.sanitize(body.to_s).squish
      raise RequestError, "Esta matéria não possui texto suficiente para reescrita." if cleaned.length < 100

      "Título original: #{@article.title}\n\nTexto-fonte:\n#{cleaned.first(30_000)}"
    end

    def parse_content(body)
      raw = JSON.parse(body).dig("choices", 0, "message", "content").to_s
      raw = raw.sub(/\A```json\s*/i, "").sub(/\s*```\z/, "")
      result = JSON.parse(raw)
      raise RequestError, "A IA não retornou título e conteúdo." if result["title"].blank? || result["content"].blank?

      result
    end
  end
end
