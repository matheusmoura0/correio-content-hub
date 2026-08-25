class ActivityLog < ApplicationRecord
  belongs_to :user

  validates :event, :description, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
