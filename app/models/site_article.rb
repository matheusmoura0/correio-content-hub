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
  CATEGORY_SLOT_GROUPS = {
    "Destaques da editoria" => [
      ["Destaque principal da editoria", "section_hero"],
      ["Destaque secundário 1", "section_feature_1"],
      ["Destaque secundário 2", "section_feature_2"]
    ],
    "Lista da editoria" => (1..9).map { |number| ["Matéria da lista #{number}", "section_list_#{number}"] }
  }.freeze
  HOME_SLOT_LABELS = SLOT_GROUPS.values.flatten(1).to_h { |label, key| [key, label] }.freeze
  CATEGORY_SLOT_LABELS = CATEGORY_SLOT_GROUPS.values.flatten(1).to_h { |label, key| [key, label] }.freeze
  SLOT_LABELS = HOME_SLOT_LABELS.merge(CATEGORY_SLOT_LABELS).freeze
  HOME_SLOT_KEYS = HOME_SLOT_LABELS.keys.freeze
  CATEGORY_SLOT_KEYS = CATEGORY_SLOT_LABELS.keys.freeze
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
  validates :slot_key, inclusion: { in: ->(_) { Publishing::SiteProfile.all_slot_keys } }, allow_blank: true
  validates :display_title, length: { maximum: 180 }, allow_blank: true
  validates :image_focus_x, :image_focus_y, inclusion: { in: 0..100 }
  validates :image_zoom, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 2 }
  validates :article_id, uniqueness: { scope: :site_id }

  def self.category_slot?(slot_key)
    CATEGORY_SLOT_KEYS.include?(slot_key)
  end

  def self.placement_for(slot_key)
    return "hero" if slot_key == "hero"
    return "editor_pick" if slot_key == "editor_pick"

    "latest"
  end

  def self.claim_automatic_slot!(distribution)
    site = distribution.site
    order = Publishing::SiteProfile.for(site).automatic_order
    occupied = site.site_articles.where(status: "published", slot_key: order)
      .where.not(id: distribution.id).pluck(:slot_key)
    slot = (order - occupied).first

    unless slot
      replaceable = site.site_articles.where(
        status: "published",
        assignment_mode: "automatic",
        slot_key: order
      ).where.not(id: distribution.id).order(:published_at, :updated_at).first
      slot = replaceable&.slot_key
      replaceable&.update!(slot_key: nil, placement: "latest", position: 0)
    end

    distribution.slot_key = slot
    distribution.assignment_mode = "automatic"
    distribution.placement = placement_for(slot)
    distribution.position = slot ? order.index(slot).to_i + 1 : 0
  end

  def slot_label
    Publishing::SiteProfile.label_for(site, slot_key) || SLOT_LABELS[slot_key] || "Sem posição fixa"
  end
end
