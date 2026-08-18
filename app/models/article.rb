class Article < ApplicationRecord
  STATUSES = %w[imported reviewing approved published ignored].freeze

  belongs_to :feed
  has_many :site_articles, dependent: :destroy
  has_many :sites, through: :site_articles

  validates :title, :source_url, :status, presence: true
  validates :source_url, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
end
