class Topic < ApplicationRecord
  MATCH_MODES = %w[any all].freeze

  has_many :topic_articles, dependent: :destroy
  has_many :articles, through: :topic_articles

  validates :name, :keywords, presence: true
  validates :match_mode, inclusion: { in: MATCH_MODES }
  validate :must_have_keywords

  def keyword_list
    keywords.to_s.split(/[\n,;]/).map(&:strip).reject(&:blank?).uniq
  end

  private

  def must_have_keywords
    errors.add(:keywords, "deve conter pelo menos um termo") if keyword_list.empty?
  end
end
