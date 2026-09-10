module Publishing
  class PopulateSite
    Result = Data.define(:published, :skipped, :eligible, :capacity)

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
      candidates = eligible_candidates.order(published_at: :desc, created_at: :desc).distinct
      capacity = automatic_capacity(profile)
      eligible = candidates.count
      published = 0
      skipped = 0

      reset_automatic_slots!(profile) if eligible.positive? && capacity.positive?

      candidates.limit([capacity * 4, 20].max).each do |article|
        break if published >= capacity

        distribution = article.site_articles.find { |item| item.site_id == @site.id }
        if !article.publication_ready? || positioned?(distribution)
          skipped += 1
          next
        end

        published += 1 if PublishArticle.call(
          article:,
          site: @site,
          category: @category,
          assignment_mode: "automatic"
        ).slot_key.present?
      rescue ActiveRecord::RecordInvalid => error
        Rails.logger.warn("Matéria #{article.id} ignorada ao popular #{@site.name}: #{error.message}")
        skipped += 1
      end

      Result.new(published:, skipped:, eligible:, capacity:)
    end

    private

    def eligible_candidates
      relation = @scope.includes(:feed, :site_articles)
      return relation unless @site.layout_profile == "cinemagazine"

      relation.where.not(image_url: nil).where.not(image_url: "").where(
        "articles.source_url LIKE :www_path OR articles.source_url LIKE :root_path",
        www_path: "https://www.correiodamanha.com.br/cultura/cinema/%",
        root_path: "https://correiodamanha.com.br/cultura/cinema/%"
      )
    end

    def automatic_capacity(profile)
      manual_slots = @site.site_articles.where(
        status: "published",
        assignment_mode: "manual",
        slot_key: profile.automatic_order
      ).distinct.count(:slot_key)

      profile.automatic_order.length - manual_slots
    end

    def reset_automatic_slots!(profile)
      @site.site_articles.where(
        status: "published",
        assignment_mode: "automatic",
        slot_key: profile.automatic_order
      ).update_all(
        slot_key: nil,
        placement: "latest",
        position: 0,
        updated_at: Time.current
      )
    end

    def positioned?(distribution)
      distribution&.status == "published" && (
        distribution.slot_key.present? || distribution.assignment_mode == "manual"
      )
    end
  end
end
