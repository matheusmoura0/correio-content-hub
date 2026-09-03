require "uri"

class Feed < ApplicationRecord
  CORREIO_DOMAINS = %w[
    correiodamanha.com.br
    correioeconomico.com.br
  ].freeze

  belongs_to :site, optional: true
  belongs_to :category, optional: true
  has_many :articles, dependent: :destroy

  validates :name, :url, presence: true
  validates :url, uniqueness: true

  def correio_source?
    host = URI.parse(url.to_s).host.to_s.downcase.sub(/\Awww\./, "")
    CORREIO_DOMAINS.any? { |domain| host == domain || host.end_with?(".#{domain}") }
  rescue URI::InvalidURIError, TypeError
    false
  end

  def publisher_name
    correio_source? ? "Correio da Manhã" : name
  end

  def publisher_url
    return unless correio_source?

    "https://www.correiodamanha.com.br"
  end
end
