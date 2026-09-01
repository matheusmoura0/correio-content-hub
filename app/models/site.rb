class Site < ApplicationRecord
  SITE_TYPES = {
    "editorial" => "Editorial",
    "hybrid" => "Híbrido",
    "catalog" => "Catálogo"
  }.freeze
  CONTENT_MODES = {
    "hub" => "Somente Content Hub",
    "external" => "Somente fonte externa",
    "hybrid" => "Content Hub + fonte externa"
  }.freeze
  LAYOUT_PROFILES = {
    "standard" => "Portal padrão",
    "gastronomy" => "Revista de Gastronomia",
    "cinemagazine" => "CINEMAGAZINE",
    "cinema_journal" => "Jornal do Cinema"
  }.freeze
  EXTERNAL_PROVIDERS = {
    "tmdb" => "The Movie Database (TMDB)"
  }.freeze

  has_many :categories, dependent: :destroy
  has_many :feeds, dependent: :nullify
  has_many :site_articles, dependent: :destroy
  has_many :articles, through: :site_articles

  validates :name, :domain, :publication_key, presence: true
  validates :domain, :publication_key, uniqueness: true
  validates :site_type, inclusion: { in: SITE_TYPES.keys }
  validates :content_mode, inclusion: { in: CONTENT_MODES.keys }
  validates :layout_profile, inclusion: { in: LAYOUT_PROFILES.keys }
  validates :external_provider, inclusion: { in: EXTERNAL_PROVIDERS.keys }, allow_blank: true

  before_validation :normalize_identifiers

  def allowed_origin_list
    allowed_origins.to_s.lines.map(&:strip).reject(&:blank?)
  end

  private

  def normalize_identifiers
    self.domain = domain.to_s.downcase.strip.sub(%r{\Ahttps?://}, "").sub(%r{/.*\z}, "")
    self.publication_key = publication_key.presence || name.to_s.parameterize
  end
end
