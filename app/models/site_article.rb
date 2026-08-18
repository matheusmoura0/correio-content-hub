class SiteArticle < ApplicationRecord
  STATUSES = %w[draft published].freeze

  belongs_to :site
  belongs_to :article
  belongs_to :category, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :article_id, uniqueness: { scope: :site_id }
end
