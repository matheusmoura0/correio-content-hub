module Correio
  class RecoverImages
    SOURCE_PATTERN = '^https?://([a-z0-9-]+[.])*(correiodamanha[.]com[.]br|correioeconomico[.]com[.]br)([:/]|$)'.freeze
    Result = Data.define(:examined, :recovered, :unavailable, :failed, :skipped, :busy)

    def self.call(limit: 15, max_duration: 30)
      counts = { examined: 0, recovered: 0, unavailable: 0, failed: 0, skipped: 0, busy: false }
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        unless connection.select_value("SELECT pg_try_advisory_lock(1952999, 3101)")
          next counts[:busy] = true
        end
        begin
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          candidates.limit(limit.clamp(1, 1000)).each do |article|
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= max_duration

            counts[:examined] += 1
            result = recover(article)
            counts[result] += 1
          end
        ensure
          connection.execute("SELECT pg_advisory_unlock(1952999, 3101)")
        end
      end
      Result.new(**counts)
    end

    def self.candidates
      destinations = Site.publication_destinations.select(:id)
      published_ids = SiteArticle.where(site_id: destinations, status: "published").select(:article_id)
      Article.joins(:feed).where(id: published_ids).where.not(status: "ignored")
        .where("feeds.url ~* ? AND articles.source_url ~* ?", SOURCE_PATTERN, SOURCE_PATTERN)
        .where(image_license: [nil, "", "owned"], image_rights_confirmed_by_id: nil)
        .where("image_url IS NULL OR image_url = '' OR image_url LIKE '%/images/logo_600x450.jpg%' OR image_url LIKE '%/imagens/bg-640x410.jpg%'")
        .where("source_enrichment_attempted_at IS NULL OR source_enrichment_attempted_at <= ?", 6.hours.ago)
        .includes(:feed)
        .order(Arel.sql("articles.source_enrichment_attempted_at ASC NULLS FIRST"),
          Arel.sql("CASE WHEN EXISTS (SELECT 1 FROM site_articles sa WHERE sa.article_id = articles.id AND sa.status = 'published' AND sa.slot_key IS NOT NULL) THEN 0 ELSE 1 END"), published_at: :desc, id: :desc)
    end

    def self.recover(article)
      return :skipped unless article.automatic_image_recovery?

      source_url = article.source_url
      original = Web::ArticleImage.normalize(article.original_image_url, base_url: source_url)
      value = original || Web::ExtractArticle.image_url(source_url)
      photo = Web::ArticleImage.normalize(value, base_url: source_url)
      article.with_lock do
        return :skipped unless article.source_url == source_url && article.automatic_image_recovery?

        attributes = { source_enrichment_attempted_at: Time.current }
        if photo
          attributes.merge!(image_url: photo, original_image_url: original || photo,
            image_source_url: source_url, image_author: article.feed.publisher_name,
            image_license: "owned", image_rights_confirmed_at: article.image_rights_confirmed_at || Time.current)
        end
        article.update!(attributes)
      end
      photo ? :recovered : :unavailable
    rescue StandardError => error
      Rails.logger.warn("Recuperação de imagem: matéria #{article.id}: #{error.class}: #{error.message}")
      Article.where(id: article.id, source_url:).update_all(source_enrichment_attempted_at: Time.current)
      :failed
    end
  end
end
