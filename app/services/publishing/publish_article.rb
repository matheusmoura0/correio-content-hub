module Publishing
  class PublishArticle
    def self.call(article:, site:, category: nil, slot_key: nil, assignment_mode: "manual")
      new(article:, site:, category:, slot_key:, assignment_mode:).call
    end

    def initialize(article:, site:, category:, slot_key:, assignment_mode:)
      @article = article
      @site = site
      @category = category
      @slot_key = slot_key.presence
      @assignment_mode = assignment_mode
    end

    def call
      raise ActiveRecord::RecordInvalid, @article unless @article.publication_ready?
      profile = SiteProfile.for(@site)
      @slot_key = nil unless profile.automatic_order.include?(@slot_key)

      Article.transaction do
        distribution = @article.site_articles.find_or_initialize_by(site: @site)
        if @slot_key
          @site.site_articles.where(status: "published", slot_key: @slot_key)
            .where.not(article_id: @article.id)
            .update_all(slot_key: nil, placement: "latest", position: 0, updated_at: Time.current)
          distribution.assign_attributes(
            slot_key: @slot_key,
            assignment_mode: @assignment_mode,
            placement: SiteArticle.placement_for(@slot_key),
            position: profile.automatic_order.index(@slot_key).to_i + 1
          )
        else
          SiteArticle.claim_automatic_slot!(distribution)
        end

        distribution.assign_attributes(
          category: @category,
          status: "published",
          published_at: Time.current
        )
        distribution.save!
        @article.update!(status: "published") unless @article.status == "published"
        distribution
      end
    end
  end
end
