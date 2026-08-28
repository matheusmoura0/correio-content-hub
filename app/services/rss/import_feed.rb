require "open-uri"

module Rss
  class ImportFeed
    Result = Data.define(:imported, :skipped)

    def self.call(feed)
      new(feed).call
    end

    def initialize(feed)
      @feed = feed
    end

    def call
      parsed = Feedjira.parse(URI.open(@feed.url, open_timeout: 5, read_timeout: 15).read)
      imported = 0
      skipped = 0

      parsed.entries.each do |entry|
        source_url = entry.url.presence || entry.entry_id.presence
        next if source_url.blank?

        data = complete_entry(entry, source_url)

        if (existing = Article.find_by(source_url: source_url))
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
          **image_rights(image_url, source_url),
          status: "imported"
        )

        distribute(article)
        imported += 1
      rescue ActiveRecord::RecordNotUnique
        skipped += 1
      rescue StandardError => error
        Rails.logger.error("Falha ao importar entrada #{source_url}: #{error.class}: #{error.message}")
        skipped += 1
      end

      @feed.update!(last_imported_at: Time.current)
      Result.new(imported:, skipped:)
    end

    private

    def complete_entry(entry, source_url)
      data = {
        title: entry.title,
        description: entry.summary,
        content: entry.content,
        author: entry.author,
        published_at: entry.published || entry.last_modified,
        image_url: extract_image(entry)
      }
      return data unless @feed.correio_source?

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
      Rails.logger.warn("Página do Correio não pôde ser complementada #{source_url}: #{error.class}: #{error.message}")
      data
    end

    def refresh_existing(article, data, source_url)
      attributes = {}
      attributes[:title] = data[:title] if data[:title].present? && article.title != data[:title]
      attributes[:description] = data[:description] if data[:description].present? && article.description.blank?
      attributes[:content] = data[:content] if data[:content].present? && article.content.to_s.length < 150
      attributes[:author] = data[:author] if data[:author].present? && article.author.blank?
      attributes[:published_at] = data[:published_at] if data[:published_at].present? && article.published_at.blank?

      image_url = article.image_url.presence || article.original_image_url.presence || data[:image_url]
      if @feed.correio_source? && image_url.present?
        attributes.merge!(
          image_url: image_url,
          original_image_url: article.original_image_url.presence || image_url,
          image_source_url: source_url,
          image_author: "Correio da Manhã",
          image_license: "owned",
          image_rights_confirmed_at: article.image_rights_confirmed_at || Time.current
        )
      end

      article.update!(attributes) if attributes.any?
    end

    def image_rights(image_url, source_url)
      return {} unless @feed.correio_source? && image_url.present?

      {
        image_source_url: source_url,
        image_author: "Correio da Manhã",
        image_license: "owned",
        image_rights_confirmed_at: Time.current
      }
    end

    def distribute(article)
      return if @feed.site.blank?

      publish_now = article.publication_ready?
      distribution = article.site_articles.find_or_initialize_by(site: @feed.site)
      if publish_now && @feed.site.domain == "revistadegastronomia.com.br" &&
          (distribution.new_record? || distribution.assignment_mode != "manual")
        SiteArticle.claim_automatic_slot!(distribution)
      end
      distribution.assign_attributes(
        category: @feed.category,
        status: publish_now ? "published" : "draft",
        published_at: publish_now ? (distribution.published_at || Time.current) : nil
      )
      distribution.slot_key = nil unless publish_now
      distribution.save!
      article.update!(status: "published") if publish_now && article.status != "published"
    end

    def extract_image(entry)
      enclosure = entry.respond_to?(:enclosure) ? entry.enclosure : nil
      return enclosure.url if enclosure.respond_to?(:url) && enclosure.url.present?

      if entry.respond_to?(:image) && entry.image.present?
        return entry.image if entry.image.is_a?(String)
        return entry.image.url if entry.image.respond_to?(:url)
      end

      html = [entry.respond_to?(:content) && entry.content, entry.respond_to?(:summary) && entry.summary].compact.join
      html[/<img[^>]+src=["']([^"']+)["']/i, 1]
    end
  end
end
