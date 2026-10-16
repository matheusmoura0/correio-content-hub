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

  def turismo_hoje_authored?
    uri = URI.parse(url.to_s)
    uri.host.to_s.downcase == "hub.cm.com.br" && uri.path == "/origens/turismo-hoje"
  rescue URI::InvalidURIError, TypeError
    false
  end

  def hub_authored?
    uri = URI.parse(url.to_s)
    uri.host.to_s.downcase == "hub.cm.com.br" && uri.path.start_with?("/origens/")
  rescue URI::InvalidURIError, TypeError
    false
  end

  def publisher_name
    return site.name if hub_authored? && site
    return "Turismo Hoje" if turismo_hoje_authored?

    correio_source? ? "Correio da Manhã" : name
  end

  def publisher_url
    return "https://#{site.domain}" if hub_authored? && site
    return "https://turismohoje.com.br" if turismo_hoje_authored?
    return unless correio_source?

    "https://www.correiodamanha.com.br"
  end
end
