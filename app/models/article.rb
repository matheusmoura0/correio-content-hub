class Article < ApplicationRecord
  STATUSES = %w[imported reviewing approved published ignored].freeze
  IMAGE_LICENSES = {
    "owned" => "Imagem própria do Correio",
    "authorized" => "Autorização direta do autor",
    "pexels" => "Pexels",
    "unsplash" => "Unsplash",
    "cc0" => "Creative Commons CC0",
    "cc_by" => "Creative Commons CC BY"
  }.freeze

  belongs_to :feed
  belongs_to :rewritten_by, class_name: "User", optional: true, inverse_of: :rewritten_articles
  belongs_to :image_rights_confirmed_by, class_name: "User", optional: true
  has_many :site_articles, dependent: :destroy
  has_many :sites, through: :site_articles
  has_many :topic_articles, dependent: :destroy
  has_many :topics, through: :topic_articles

  before_validation :separate_unverified_imported_image, on: :create

  validates :title, :source_url, :status, presence: true
  validates :source_url, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :image_license, inclusion: { in: IMAGE_LICENSES.keys }, allow_blank: true
  validates :image_url, :image_source_url, :image_license, presence: true, if: :image_rights_confirmed_at?
  validates :image_author, presence: true, if: -> { image_rights_confirmed_at? && image_license.in?(%w[authorized pexels unsplash cc_by]) }
  validates :image_license_url, presence: true, if: -> { image_rights_confirmed_at? && image_license.in?(%w[pexels unsplash cc0 cc_by]) }

  def licensed_image_ready?
    image_url.present? && image_source_url.present? && image_license.present? &&
      image_rights_confirmed_at.present? &&
      (image_rights_confirmed_by.present? || trusted_correio_image?)
  end

  def trusted_correio_image?
    feed.correio_source? && image_license == "owned"
  end

  def publication_ready?
    feed.correio_source? || licensed_image_ready?
  end

  def image_optional?
    feed.correio_source?
  end

  private

  def separate_unverified_imported_image
    return if image_url.blank? || image_rights_confirmed_at.present?

    self.original_image_url ||= image_url
    self.image_url = nil
  end

  public

  def image_credit
    return if image_author.blank?

    [image_author, IMAGE_LICENSES[image_license]].compact.join(" · ")
  end
end
