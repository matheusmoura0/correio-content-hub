require "uri"

class AnalyticsAuthorProfile < ApplicationRecord
  belongs_to :site
  scope :columnists, -> { where(active: true, individual: true) }

  before_validation :normalize_aliases
  validates :name, :slug, :source_url, presence: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }, uniqueness: { scope: :site_id }
  validate :trusted_source
  validate :unambiguous_aliases

  def self.trusted_url?(value)
    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTP) && %w[correiodamanha.com.br www.correiodamanha.com.br].include?(uri.host) && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  private

  def normalize_aliases
    self.aliases = ([name] + Array(aliases)).map { |value| Analytics::AuthorIdentity.normalize(value) }.reject(&:blank?).uniq
  end

  def trusted_source
    errors.add(:site, "deve ser o Correio da Manhã") unless site&.correio_source?
    errors.add(:source_url, "deve ser o perfil oficial") unless self.class.trusted_url?(source_url) && URI.parse(source_url).path == "/colunistas/#{slug}"
    if image_url.present? && (!self.class.trusted_url?(image_url) || Web::ArticleImage.placeholder?(image_url))
      errors.add(:image_url, "deve ser uma foto oficial do perfil")
    end
  end

  def unambiguous_aliases
    return unless individual? && active? && site_id && aliases.any?

    others = self.class.columnists.where(site_id: site_id).where.not(id: id)
    if others.where("aliases && ARRAY[?]::varchar[]", aliases).exists?
      errors.add(:aliases, "já identificam outro colunista")
    end
  end
end
