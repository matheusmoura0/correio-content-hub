module Topics
  class RunSearch
    Result = Data.define(:matches, :imported, :skipped, :feed_errors)

    def self.call(topic)
      new(topic).call
    end

    def initialize(topic)
      @topic = topic
    end

    def call
      imported = 0
      skipped = 0
      feed_errors = []

      Feed.where(active: true).find_each do |feed|
        result = Rss::ImportFeed.call(feed)
        imported += result.imported
        skipped += result.skipped
      rescue StandardError => error
        Rails.logger.error("Falha ao importar #{feed.url}: #{error.class}: #{error.message}")
        feed_errors << feed.name
      end

      matches = match_articles
      @topic.update!(last_run_at: Time.current)
      Result.new(matches:, imported:, skipped:, feed_errors:)
    end

    private

    def match_articles
      terms = @topic.keyword_list
      normalized_terms = terms.to_h { |term| [term, normalize(term)] }
      count = 0
      matching_article_ids = []

      Article.find_each do |article|
        haystack = normalize([article.title, article.description, article.content].compact.join(" "))
        matched = normalized_terms.filter_map { |original, normalized| original if haystack.include?(normalized) }
        qualifies = @topic.match_mode == "all" ? matched.size == terms.size : matched.any?
        next unless qualifies && terms.any?

        matching_article_ids << article.id
        relation = @topic.topic_articles.find_or_initialize_by(article:)
        relation.matched_terms = matched.join(", ")
        count += 1 if relation.new_record?
        relation.save!
      end


      @topic.topic_articles.where.not(article_id: matching_article_ids).delete_all

      count
    end

    def normalize(value)
      ActionView::Base.full_sanitizer.sanitize(value.to_s).unicode_normalize(:nfkd)
        .encode("ASCII", invalid: :replace, undef: :replace, replace: "").downcase
    end
  end
end
