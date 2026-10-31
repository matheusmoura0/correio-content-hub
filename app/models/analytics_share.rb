class AnalyticsShare < ApplicationRecord
  belongs_to :site
  has_secure_token :token, length: 32

  validates :site_id, uniqueness: true
  validate :supported_publication

  def available?
    site.active? && site.correio_source? && !site.retired_from_hub?
  end

  private

  def supported_publication
    errors.add(:site, "deve ser o Correio da Manhã ativo") unless site && available?
  end
end
