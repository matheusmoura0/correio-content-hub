class EditorialEditionItem < ApplicationRecord
  belongs_to :editorial_edition
  belongs_to :article
  belongs_to :category, optional: true
  validates :slot_key, :article_digest, :title, presence: true
end
