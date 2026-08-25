require "json"
require "net/http"

module Web
  class SearchTopic
    Result = Data.define(:imported, :skipped, :errors)
    ENDPOINT = URI("https://api.openai.com/v1/responses")

    def self.call(topic)
      new(topic).call
    end

    def initialize(topic)
      @topic = topic
    end

    def call
      token = ENV["OPENAI_API_KEY"]
      raise "Configure OPENAI_API_KEY no servidor" if token.blank?

      candidates = search(token)
      feed = Feed.find_or_create_by!(url: "internal://openai-web-search") do |record|
        record.name = "Busca na web"
        record.active = false
      end

      imported = 0
      skipped = 0
      errors = []

      candidates.first(10).each do |candidate|
        url = candidate["url"].to_s
        if url.blank?
          skipped += 1
          next
        end

        if (existing = Article.find_by(source_url: url))
          @topic.topic_articles.find_or_create_by!(article: existing) do |match|
            match.matched_terms = @topic.keyword_list.join(", ")
          end
          skipped += 1
          next
        end

        extracted = ExtractArticle.call(url)
        article = feed.articles.create!(
          title: extracted.title.presence || candidate["title"].presence || "Sem título",
          description: extracted.description.presence || candidate["summary"],
          content: extracted.content,
          image_url: extracted.image_url,
          author: extracted.author,
          source_url: url,
          published_at: extracted.published_at || parse_time(candidate["published_at"]),
          status: "imported"
        )
        @topic.topic_articles.create!(article:, matched_terms: @topic.keyword_list.join(", "))
        imported += 1
      rescue StandardError => error
        Rails.logger.error("Falha ao coletar #{url}: #{error.class}: #{error.message}")
        errors << candidate["title"].presence || url
      end

      Result.new(imported:, skipped:, errors:)
    end

    private

    def search(token)
      request = Net::HTTP::Post.new(ENDPOINT)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request.body = request_body.to_json
      response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 10, read_timeout: 90) { |http| http.request(request) }
      raise api_error(response) unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body)
      raw = parsed.fetch("output", []).flat_map { |item| item.fetch("content", []) }
        .find { |content| content["type"] == "output_text" }&.fetch("text", "").to_s
      JSON.parse(raw).fetch("articles", [])
    end

    def api_error(response)
      error = JSON.parse(response.body).fetch("error", {})
      code = error["code"].presence || error["type"].presence

      message = case code
      when "credit_balance_exhausted", "insufficient_quota"
        "A conta da OpenAI API está sem créditos. Adicione saldo em platform.openai.com/settings/organization/billing."
      when "project_spend_limit_exceeded"
        "O limite mensal do projeto da OpenAI foi atingido. Aumente-o em Project settings → Limits."
      when "organization_spend_limit_exceeded", "organization_usage_limit_exceeded"
        "O limite da organização na OpenAI foi atingido. Verifique Organization settings → Limits."
      when "rate_limit_exceeded"
        "A OpenAI limitou temporariamente as requisições. Aguarde um minuto e tente novamente."
      else
        error["message"].presence || "A busca web respondeu com HTTP #{response.code}."
      end

      "#{message} (#{code || "HTTP #{response.code}"})"
    rescue JSON::ParserError
      "A busca web respondeu com HTTP #{response.code}."
    end

    def request_body
      {
        model: ENV.fetch("OPENAI_SEARCH_MODEL", ENV.fetch("OPENAI_MODEL", "gpt-5.6-luna")),
        tools: [{ type: "web_search", external_web_access: true }],
        tool_choice: "auto",
        include: ["web_search_call.action.sources"],
        store: false,
        input: search_prompt,
        text: { format: response_format }
      }
    end

    def search_prompt
      rule = @topic.match_mode == "all" ? "todos os termos" : "pelo menos um dos termos"
      <<~PROMPT
        Pesquise na web matérias jornalísticas atuais em português relacionadas a: #{@topic.keyword_list.join(', ')}.
        Cada resultado deve corresponder a #{rule}. Retorne até 10 matérias de fontes distintas quando possível.
        Inclua somente URLs diretas de matérias, nunca páginas iniciais, categorias, buscas, redes sociais ou arquivos PDF.
      PROMPT
    end

    def response_format
      {
        type: "json_schema",
        name: "web_articles",
        strict: true,
        schema: {
          type: "object",
          properties: {
            articles: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  title: { type: "string" },
                  url: { type: "string" },
                  summary: { type: "string" },
                  published_at: { type: ["string", "null"] }
                },
                required: %w[title url summary published_at],
                additionalProperties: false
              }
            }
          },
          required: ["articles"],
          additionalProperties: false
        }
      }
    end

    def parse_time(value)
      Time.zone.parse(value) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
