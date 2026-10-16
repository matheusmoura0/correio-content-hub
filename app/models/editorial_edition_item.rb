class EditorialEditionItem < ApplicationRecord
  belongs_to :editorial_edition
  belongs_to :article
  belongs_to :category, optional: true
  belongs_to :decided_by, class_name: "User", optional: true
  scope :pending, -> { where(decision: "pending") }
  validates :decision, inclusion: { in: %w[pending approved rejected skipped] }
  validates :slot_key, :article_digest, :title, presence: true
end
