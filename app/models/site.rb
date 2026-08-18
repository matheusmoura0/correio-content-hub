class Site < ApplicationRecord
  has_many :categories, dependent: :destroy
  has_many :feeds, dependent: :nullify
  has_many :site_articles, dependent: :destroy
  has_many :articles, through: :site_articles

  validates :name, :domain, presence: true
  validates :domain, uniqueness: true
end
