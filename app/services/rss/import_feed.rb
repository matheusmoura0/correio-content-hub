require "open-uri"
require "nokogiri"
require "set"

module Rss
  class ImportFeed
    CINEMA_FEED_URL = "https://www.correiodamanha.com.br/cultura/cinema/sitemap-rss.xml".freeze
    CINEMA_SECTION_URL = "https://www.correiodamanha.com.br/cultura/cinema".freeze
    CINEMA_ARTICLE_PATH = %r{\A/cultura/cinema/\d{4}/\d{2}/\d+-[^/?#]+\.html\z}.freeze
    MAX_SECTION_BYTES = 2_000_000
    DiscoveredEntry = Struct.new(
      :url, :entry_id, :title, :summary, :content, :author,
      :published, :last_modified, :enclosure, :image,
      keyword_init: true
    )
    Result = Data.define(:imported, :skipped, :warnings)

    def self.call(feed)
      new(feed).call
    end

    def initialize(feed)
      @feed = feed
      @warnings = 0
    end

    def call
      @warnings = 0
      parsed = Feedjira.parse(URI.open(@feed.url, open_timeout: 5, read_timeout: 15).read)
      imported = 0
      skipped = 0

      entries_for(parsed).each do |entry|
        source_url = entry.url.presence || entry.entry_id.presence
        next if source_url.blank?

        existing = Article.find_by(source_url: source_url)
        @enrichment_attempted_at = nil
        data = complete_entry(entry, source_url, existing:)

        if existing
          refresh_existing(existing, data, source_url)
          distribute(existing)
          skipped += 1
          next
        end

        image_url = data[:image_url]
        article = @feed.articles.create!(
          title: data[:title].presence || "Sem título",
          description: data[:description],
          content: data[:content],
          author: data[:author],
          source_url: source_url,
          guid: entry.entry_id,
          published_at: data[:published_at],
          image_url: image_url,
          original_image_url: image_url,
          source_enrichment_attempted_at: @enrichment_attempted_at,
          **image_rights(image_url, source_url),
          status: "imported"
        )

        distribute(article)
        imported += 1
      rescue ActiveRecord::RecordNotUnique
        skipped += 1
      rescue StandardError => error
        @warnings += 1
        Rails.logger.error("Falha ao importar entrada #{source_url}: #{error.class}: #{error.message}")
        skipped += 1
      end

      @feed.update!(last_imported_at: Time.current, last_import_warning_count: @warnings)
      Result.new(imported:, skipped:, warnings: @warnings)
    end

    private

    def entries_for(parsed)
      rss_entries = parsed.entries.to_a
      return rss_entries unless cinema_feed?

      known_urls = rss_entries.filter_map { |entry| canonical_url(entry.url.presence || entry.entry_id.presence) }.to_set
      rss_entries + cinema_section_urls.filter_map do |url|
        next if known_urls.include?(url)

        DiscoveredEntry.new(url:, entry_id: url)
      end
    rescue StandardError => error
      @warnings += 1
      Rails.logger.warn("Página de Cinema não pôde complementar o RSS: #{error.class}: #{error.message}")
      rss_entries
    end

    def cinema_feed?
      canonical_url(@feed.url) == CINEMA_FEED_URL
    end

    def cinema_section_urls
      html = URI.open(
        CINEMA_SECTION_URL,
        "User-Agent" => "CorreioContentHub/1.0 (+editorial import)",
        "Accept" => "text/html,application/xhtml+xml",
        open_timeout: 10,
        read_timeout: 20
      ).read(MAX_SECTION_BYTES + 1)
      raise "Página da editoria excedeu o tamanho permitido" if html.bytesize > MAX_SECTION_BYTES

      document = Nokogiri::HTML(html)
      document.css("a[href]").filter_map do |link|
        url = canonical_url(URI.join(CINEMA_SECTION_URL, link["href"]).to_s)
        uri = URI.parse(url) if url.present?
        url if uri&.path&.match?(CINEMA_ARTICLE_PATH)
      rescue URI::InvalidURIError
        nil
      end.uniq
    end

    def canonical_url(value)
      uri = URI.parse(value.to_s)
      return unless uri.is_a?(URI::HTTP)
      return unless uri.host.to_s.downcase.sub(/\Awww\./, "") == "correiodamanha.com.br"

      uri.scheme = "https"
      uri.host = "www.correiodamanha.com.br"
      uri.query = nil
      uri.fragment = nil
      uri.to_s.sub(%r{/\z}, "")
    rescue URI::InvalidURIError
      nil
    end

    def complete_entry(entry, source_url, existing: nil)
      data = {
        title: entry.title,
        description: entry.summary,
        content: entry.content,
        author: entry.author,
        published_at: entry.published || entry.last_modified,
        image_url: extract_image(entry)
      }
      return data unless @feed.correio_source? && Feed.correio_url?(source_url)
      complete_text = existing && ActionController::Base.helpers.strip_tags(existing.content.to_s).strip.length >= 150
      needs_image = existing&.automatic_image_recovery?
      return data if complete_text && !needs_image
      if existing&.source_enrichment_attempted_at && existing.source_enrichment_attempted_at > 6.hours.ago
        @warnings += 1
        return data
      end

      @enrichment_attempted_at = Time.current
      if complete_text
        image_url = Web::ExtractArticle.image_url(source_url)
        return data.merge(image_url: image_url.presence || data[:image_url])
      end
      extracted = Web::ExtractArticle.call(source_url)
      data.merge(
        title: extracted.title.presence || data[:title],
        description: extracted.description.presence || data[:description],
        content: extracted.content.presence || data[:content],
        author: extracted.author.presence || data[:author],
        published_at: extracted.published_at || data[:published_at],
        image_url: extracted.image_url.presence || data[:image_url]
      )
    rescue StandardError => error
      @warnings += 1
      Rails.logger.warn("Página do Correio não pôde ser complementada #{source_url}: #{error.class}: #{error.message}")
      data
    end

    def refresh_existing(article, data, source_url)
      attributes = {}
      attributes[:source_enrichment_attempted_at] = @enrichment_attempted_at if @enrichment_attempted_at
      attributes[:title] = data[:title] if data[:title].present? && article.title != data[:title]
      attributes[:description] = data[:description] if data[:description].present? && article.description.blank?
      attributes[:content] = data[:content] if data[:content].present? && article.content.to_s.length < 150
      attributes[:author] = data[:author] if data[:author].present? && article.author.blank?
      attributes[:published_at] = data[:published_at] if data[:published_at].present? && article.published_at.blank?

      image_url = [article.image_url, article.original_image_url, data[:image_url]].filter_map do |value|
        Web::ArticleImage.normalize(value, base_url: source_url)
      end.first
      if @feed.correio_source? && Feed.correio_url?(source_url) && image_url.present? &&
          article.image_rights_confirmed_by_id.nil? && article.image_license.in?([nil, "", "owned"])
        attributes.merge!(
          image_url: image_url,
          original_image_url: Web::ArticleImage.normalize(article.original_image_url, base_url: source_url) || image_url,
          image_source_url: source_url,
          image_author: "Correio da Manhã",
          image_license: "owned",
          image_rights_confirmed_at: article.image_rights_confirmed_at || Time.current
        )
      end

      article.update!(attributes) if attributes.any?
    end

    def image_rights(image_url, source_url)
      return {} unless @feed.correio_source? && Feed.correio_url?(source_url) && image_url.present? && !Web::ArticleImage.placeholder?(image_url)

      {
        image_source_url: source_url,
        image_author: "Correio da Manhã",
        image_license: "owned",
        image_rights_confirmed_at: Time.current
      }
    end

    def distribute(article)
      return unless @feed.site&.publication_destination?

      # Imports may stage content, but never change an existing editorial decision.
      @feed.site.with_lock do
        distribution = article.site_articles.find_or_initialize_by(site: @feed.site)
        return if distribution.persisted?

        category = @feed.category if @feed.category&.site_id == @feed.site_id
        distribution.assign_attributes(category:, status: "draft")
        distribution.save!
      end
    end

    def extract_image(entry)
      base_url = entry.url.presence || @feed.url
      enclosure = entry.respond_to?(:enclosure) ? entry.enclosure : nil
      value = enclosure.url if enclosure.respond_to?(:url)
      value ||= enclosure["url"] || enclosure[:url] if enclosure.is_a?(Hash)
      candidate = Web::ArticleImage.normalize(value, base_url:)
      return candidate if candidate

      if entry.respond_to?(:image) && entry.image.present?
        value = entry.image.is_a?(String) ? entry.image : entry.image.respond_to?(:url) ? entry.image.url : nil
        candidate = Web::ArticleImage.normalize(value, base_url:)
        return candidate if candidate
      end

      html = [entry.respond_to?(:content) && entry.content, entry.respond_to?(:summary) && entry.summary].compact.join
      fragment = Nokogiri::HTML.fragment(html)
      fragment.css("img").each do |image|
        [image["data-src"], image["data-lazy-src"], image["src"]].each do |value|
          candidate = Web::ArticleImage.normalize(value, base_url:)
          return candidate if candidate
        end
      end
      nil
    end
  end
end
