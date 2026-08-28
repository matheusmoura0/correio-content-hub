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

        if (existing = Article.find_by(source_url: source_url))
          prepare_owned_image(existing, entry, source_url)
          distribute(existing)
          skipped += 1
          next
        end

        image_url = extract_image(entry)
        article = @feed.articles.create!(
          title: entry.title.presence || "Sem título",
          description: entry.summary,
          content: entry.content,
          author: entry.author,
          source_url: source_url,
          guid: entry.entry_id,
          published_at: entry.published || entry.last_modified,
          image_url: image_url,
          original_image_url: image_url,
          **image_rights(image_url, source_url),
          status: "imported"
        )

        distribute(article)
        imported += 1
      rescue ActiveRecord::RecordNotUnique
        skipped += 1
      end

      @feed.update!(last_imported_at: Time.current)
      Result.new(imported:, skipped:)
    end

    private

    def image_rights(image_url, source_url)
      return {} unless @feed.correio_source? && image_url.present?

      {
        image_source_url: source_url,
        image_author: "Correio da Manhã",
        image_license: "owned",
        image_rights_confirmed_at: Time.current
      }
    end

    def prepare_owned_image(article, entry, source_url)
      image_url = article.image_url.presence || article.original_image_url.presence || extract_image(entry)
      return unless @feed.correio_source? && image_url.present?

      article.update!(
        image_url: image_url,
        original_image_url: article.original_image_url.presence || image_url,
        image_source_url: source_url,
        image_author: "Correio da Manhã",
        image_license: "owned",
        image_rights_confirmed_at: article.image_rights_confirmed_at || Time.current
      )
    end

    def distribute(article)
      return if @feed.site.blank?

      publish_now = @feed.correio_source? && article.licensed_image_ready?
      distribution = article.site_articles.find_or_initialize_by(site: @feed.site)
      distribution.assign_attributes(
        category: @feed.category,
        status: publish_now ? "published" : "draft",
        published_at: publish_now ? (distribution.published_at || Time.current) : nil
      )
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
