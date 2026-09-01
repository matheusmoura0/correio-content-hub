module Publishing
  class PopulateSite
    Result = Data.define(:published, :skipped)

    def self.call(site:, scope:, category: nil)
      new(site:, scope:, category:).call
    end

    def initialize(site:, scope:, category:)
      @site = site
      @scope = scope
      @category = category
    end

    def call
      profile = SiteProfile.for(@site)
      candidates = @scope.includes(:feed).order(published_at: :desc, created_at: :desc).distinct
      published = 0
      skipped = 0

      candidates.limit(profile.automatic_order.length * 4).each do |article|
        break if published >= profile.automatic_order.length
        if !article.publication_ready? || article.site_articles.exists?(site: @site, status: "published")
          skipped += 1
          next
        end

        PublishArticle.call(article:, site: @site, category: @category, assignment_mode: "automatic")
        published += 1
      rescue ActiveRecord::RecordInvalid => error
        Rails.logger.warn("Matéria #{article.id} ignorada ao popular #{@site.name}: #{error.message}")
        skipped += 1
      end

      Result.new(published:, skipped:)
    end
  end
end
