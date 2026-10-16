require "digest"

class EditorialEdition < ApplicationRecord
  belongs_to :site
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :items, class_name: "EditorialEditionItem", dependent: :destroy
  validates :status, inclusion: { in: %w[ready approved rejected expired] }
  validates :page_digest, presence: true

  def finish_decisions!(user, approved: false)
    attributes = { page_digest: self.class.page_digest(site) }
    unless items.pending.exists?
      attributes[:status] = items.where(decision: "approved").exists? ? "approved" : "rejected"
    end
    if approved
      attributes.merge!(approved_by: user, approved_at: Time.current)
    end
    update!(attributes)
  end

  def self.page_digest(site)
    snapshot = {
      policy: site.attributes.slice("active", "receives_hub_content", "editorial_keywords", "layout_profile"),
      categories: site.categories.order(:id).pluck(:id, :name, :slug),
      publications: site.site_articles.where(status: "published").order(:id)
        .pluck(:id, :article_id, :category_id, :slot_key, :assignment_mode, :updated_at)
    }
    Digest::SHA256.hexdigest(snapshot.to_json)
  end

  def self.article_digest(article)
    Digest::SHA256.hexdigest(article.attributes.except("updated_at", "status").sort.to_json)
  end
end
