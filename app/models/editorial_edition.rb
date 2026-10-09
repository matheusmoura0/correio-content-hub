require "digest"

class EditorialEdition < ApplicationRecord
  belongs_to :site
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :items, class_name: "EditorialEditionItem", dependent: :destroy
  validates :status, inclusion: { in: %w[ready approved rejected] }
  validates :page_digest, presence: true

  def self.page_digest(site)
    Digest::SHA256.hexdigest(site.site_articles.where(status: "published").order(:id)
      .pluck(:id, :article_id, :category_id, :slot_key, :assignment_mode, :updated_at).to_json)
  end

  def self.article_digest(article)
    Digest::SHA256.hexdigest(article.attributes.except("updated_at", "status").sort.to_json)
  end
end
