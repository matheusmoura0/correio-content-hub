class TopicArticle < ApplicationRecord
  belongs_to :topic
  belongs_to :article

  validates :article_id, uniqueness: { scope: :topic_id }
end
