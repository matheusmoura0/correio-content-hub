class SiteArticle < ApplicationRecord
  STATUSES = %w[draft published].freeze
  PLACEMENTS = %w[latest hero editor_pick].freeze
  ASSIGNMENT_MODES = %w[manual automatic].freeze

  SLOT_GROUPS = {
    "Destaques" => [
      ["Manchete principal", "hero"],
      ["Escolha do editor", "editor_pick"]
    ],
    "Novidades" => (1..6).map { |number| ["Card de novidades #{number}", "fresh_#{number}"] },
    "Agora" => (1..3).map { |number| ["Chamada do ticker #{number}", "breaking_#{number}"] },
    "Mais lidas" => (1..5).map { |number| ["Item mais lido #{number}", "popular_#{number}"] }
  }.freeze
  SLOT_LABELS = SLOT_GROUPS.values.flatten(1).to_h { |label, key| [key, label] }.freeze
  SLOT_KEYS = SLOT_LABELS.keys.freeze
  AUTOMATIC_SLOT_ORDER = %w[
    fresh_1 fresh_2 fresh_3 fresh_4 fresh_5 fresh_6
    breaking_1 breaking_2 breaking_3
    popular_1 popular_2 popular_3 popular_4 popular_5
  ].freeze

  belongs_to :site
  belongs_to :article
  belongs_to :category, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :placement, inclusion: { in: PLACEMENTS }
  validates :assignment_mode, inclusion: { in: ASSIGNMENT_MODES }
  validates :slot_key, inclusion: { in: SLOT_KEYS }, allow_blank: true
  validates :article_id, uniqueness: { scope: :site_id }

  def self.placement_for(slot_key)
    return "hero" if slot_key == "hero"
    return "editor_pick" if slot_key == "editor_pick"

    "latest"
  end

  def self.claim_automatic_slot!(distribution)
    site = distribution.site
    occupied = site.site_articles.where(status: "published", slot_key: AUTOMATIC_SLOT_ORDER)
      .where.not(id: distribution.id).pluck(:slot_key)
    slot = (AUTOMATIC_SLOT_ORDER - occupied).first

    unless slot
      replaceable = site.site_articles.where(
        status: "published",
        assignment_mode: "automatic",
        slot_key: AUTOMATIC_SLOT_ORDER
      ).where.not(id: distribution.id).order(:published_at, :updated_at).first
      slot = replaceable&.slot_key
      replaceable&.update!(slot_key: nil, placement: "latest", position: 0)
    end

    distribution.slot_key = slot
    distribution.assignment_mode = "automatic"
    distribution.placement = placement_for(slot)
    distribution.position = slot ? AUTOMATIC_SLOT_ORDER.index(slot).to_i + 1 : 0
  end

  def slot_label
    SLOT_LABELS[slot_key] || "Sem posição fixa"
  end
end
