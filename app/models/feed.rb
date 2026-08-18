class Feed < ApplicationRecord
  belongs_to :site, optional: true
  belongs_to :category, optional: true
  has_many :articles, dependent: :destroy

  validates :name, :url, presence: true
  validates :url, uniqueness: true
end
