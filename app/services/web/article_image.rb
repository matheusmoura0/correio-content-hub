require "json"
require "uri"

module Web
  class ArticleImage
    def self.placeholder?(value)
      path = URI.parse(value.to_s).path.to_s.downcase
      path.match?(%r{\A/(?:images|imagens)/(?:logo(?:[_-][^/]*)?|bg-\d+x\d+|favicon[^/]*|correio-da-manha-linha-vermelha)\.(?:jpe?g|png|webp|svg|ico)\z})
    rescue URI::InvalidURIError
      false
    end

    def self.normalize(value, base_url:)
      return unless value.is_a?(String) && value.present?

      uri = URI.join(base_url.to_s, value.strip)
      return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      return if placeholder?(uri.to_s)

      uri.to_s
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    def self.call(document, base_url:)
      values = document.css('meta[property="og:image:secure_url"],meta[property="og:image"],meta[name="twitter:image"],meta[property="twitter:image"],meta[name="twitter:image:src"],meta[property="twitter:image:src"]').map { |node| node["content"] }
      document.css('script[type="application/ld+json"]').each do |script|
        begin
          values.concat(article_images(JSON.parse(script.text)))
        rescue JSON::ParserError
          next
        end
      end

      title = document.at_css("h1")&.text.to_s.squish.downcase
      document.css("article img, main img").each do |node|
        next if title.blank? || node["alt"].to_s.squish.downcase != title
        next if node.ancestors.any? { |parent| parent.name.in?(%w[aside nav footer]) }

        values.concat([node["data-src"], node["data-lazy-src"], node["src"]])
      end
      values.each do |value|
        url = normalize(value, base_url:)
        return url if url
      end
      nil
    end

    def self.article_images(data)
      case data
      when Array
        data.flat_map { |item| article_images(item) }
      when Hash
        images = Array(data["@type"]).intersect?(%w[NewsArticle Article BlogPosting]) ? image_values(data["image"]) : []
        images + article_images(data["@graph"]) + article_images(data["mainEntity"])
      else
        []
      end
    end

    def self.image_values(data)
      case data
      when Array then data.flat_map { |item| image_values(item) }
      when Hash then [data["contentUrl"], data["url"]].compact
      when String then [data]
      else []
      end
    end
  end
end
