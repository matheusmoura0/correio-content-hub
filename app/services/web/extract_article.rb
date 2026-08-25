require "ipaddr"
require "net/http"
require "nokogiri"
require "resolv"
require "uri"

module Web
  class ExtractArticle
    Result = Data.define(:title, :content, :description, :image_url, :author, :published_at)
    MAX_REDIRECTS = 3
    MAX_BODY_BYTES = 2_000_000

    def self.call(url)
      new(url).call
    end

    def initialize(url)
      @url = url
    end

    def call
      html, final_url = fetch(@url)
      document = Nokogiri::HTML(html)
      document.css("script, style, nav, footer, header, aside, form, noscript").remove

      paragraphs = article_paragraphs(document)
      content = paragraphs.map { |node| node.text.squish }.select { |text| text.length >= 40 }.uniq.join("\n\n")
      raise "Não foi possível extrair o texto da página" if content.length < 150

      Result.new(
        title: meta(document, "property", "og:title") || document.at_css("h1")&.text&.squish,
        content: content.first(30_000),
        description: meta(document, "property", "og:description") || meta(document, "name", "description"),
        image_url: absolute_url(meta(document, "property", "og:image"), final_url),
        author: meta(document, "name", "author"),
        published_at: parse_time(meta(document, "property", "article:published_time")),
      )
    end

    private

    def fetch(url, redirects = 0)
      raise "Muitos redirecionamentos" if redirects > MAX_REDIRECTS

      uri = URI.parse(url)
      validate_public_uri!(uri)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "CorreioContentHub/1.0 (+article research)"
      request["Accept"] = "text/html,application/xhtml+xml"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
        http.request(request)
      end

      if response.is_a?(Net::HTTPRedirection) && response["location"].present?
        return fetch(URI.join(uri.to_s, response["location"]).to_s, redirects + 1)
      end
      raise "Página respondeu com HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      [response.body.to_s.byteslice(0, MAX_BODY_BYTES), uri]
    end

    def validate_public_uri!(uri)
      raise "URL inválida" unless uri.is_a?(URI::HTTP) && uri.host.present?

      addresses = Resolv.getaddresses(uri.host)
      raise "Endereço não resolvido" if addresses.empty?
      raise "Endereço privado não permitido" if addresses.any? { |address| private_address?(IPAddr.new(address)) }
    end

    def private_address?(ip)
      ranges = %w[0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 ::1/128 fc00::/7 fe80::/10]
      ranges.any? { |range| IPAddr.new(range).include?(ip) }
    end

    def article_paragraphs(document)
      selectors = ["[itemprop='articleBody'] p", "article p", "main p"]
      selectors.each do |selector|
        nodes = document.css(selector)
        return nodes if nodes.sum { |node| node.text.length } >= 300
      end
      document.css("body p")
    end

    def meta(document, attribute, value)
      document.at_css("meta[#{attribute}='#{value}']")&.[]("content")&.squish.presence
    end

    def absolute_url(value, base)
      URI.join(base.to_s, value).to_s if value.present?
    rescue URI::InvalidURIError
      nil
    end

    def parse_time(value)
      Time.zone.parse(value) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
