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
      parsed = Feedjira.parse(URI.open(@feed.url, read_timeout: 15).read)
      imported = 0
      skipped = 0

      parsed.entries.each do |entry|
        source_url = entry.url.presence || entry.entry_id.presence
        next if source_url.blank?

        if Article.exists?(source_url: source_url)
          skipped += 1
          next
        end

        article = @feed.articles.create!(
          title: entry.title.presence || "Sem título",
          description: entry.summary,
          content: entry.content,
          author: entry.author,
          source_url: source_url,
          guid: entry.entry_id,
          published_at: entry.published || entry.last_modified,
          image_url: extract_image(entry),
          status: "imported"
        )

        if @feed.site.present?
          article.site_articles.create!(
            site: @feed.site,
            category: @feed.category,
            status: "draft"
          )
        end

        imported += 1
      rescue ActiveRecord::RecordNotUnique
        skipped += 1
      end

      @feed.update!(last_imported_at: Time.current)
      Result.new(imported:, skipped:)
    end

    private

    def extract_image(entry)
      enclosure = entry.respond_to?(:enclosure) ? entry.enclosure : nil
      return enclosure.url if enclosure.respond_to?(:url) && enclosure.url.present?

      nil
    end
  end
end
