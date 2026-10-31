class Category < ApplicationRecord
  belongs_to :site
  has_many :feeds, dependent: :nullify
  has_many :site_articles, dependent: :nullify

  validates :name, :slug, presence: true
  validates :slug, uniqueness: { scope: :site_id }
end
