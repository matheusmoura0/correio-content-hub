class Article < ApplicationRecord
  STATUSES = %w[imported reviewing approved published ignored].freeze

  belongs_to :feed
  belongs_to :rewritten_by, class_name: "User", optional: true, inverse_of: :rewritten_articles
  has_many :site_articles, dependent: :destroy
  has_many :sites, through: :site_articles
  has_many :topic_articles, dependent: :destroy
  has_many :topics, through: :topic_articles

  validates :title, :source_url, :status, presence: true
  validates :source_url, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
end
