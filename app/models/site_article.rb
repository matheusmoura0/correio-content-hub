class SiteArticle < ApplicationRecord
  STATUSES = %w[draft published].freeze
  PLACEMENTS = %w[latest hero editor_pick].freeze

  belongs_to :site
  belongs_to :article
  belongs_to :category, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :placement, inclusion: { in: PLACEMENTS }
  validates :article_id, uniqueness: { scope: :site_id }
end
