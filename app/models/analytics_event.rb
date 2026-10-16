class AnalyticsEvent < ApplicationRecord
  EVENT_TYPES = %w[page_view click engagement].freeze

  belongs_to :site

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, :path, :session_hash, :visitor_hash, :device_type, presence: true
  validates :value, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 86_400 }
end
