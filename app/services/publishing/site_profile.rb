module Publishing
  class SiteProfile
    Profile = Data.define(:key, :label, :groups, :automatic_order)

    ICARO_SECTIONS = {
      "destinos" => "Destinos", "roteiros" => "Roteiros", "hospedagem" => "Hospedagem",
      "sabores" => "Sabores", "aviacao" => "Aviação", "guia-do-viajante" => "Guia do viajante"
    }.freeze

    def self.icaro_section_slots(slug)
      return [] unless ICARO_SECTIONS.key?(slug)
      (1..12).map { |n| "section_icaro_#{slug}_#{n}" }
    end

    def self.slot_keys(site)
      self.for(site).groups.values.flatten(1).map(&:last)
    end

    PROFILES = {
      "tourism" => Profile.new(
        key: "tourism",
        label: "Jornal de Turismo",
        groups: {
          "Capa" => [["Manchete principal", "hero"], ["Escolha do editor", "tourism_editor_pick"]],
          "Chamadas" => (1..3).map { |n| ["Chamada #{n}", "tourism_brief_#{n}"] },
          "Destinos e roteiros" => (1..6).map { |n| ["Matéria #{n}", "tourism_card_#{n}"] },
          "Aviação" => (1..2).map { |n| ["Aviação #{n}", "tourism_aviation_#{n}"] }
        },
        automatic_order: %w[hero tourism_editor_pick tourism_brief_1 tourism_brief_2 tourism_brief_3 tourism_card_1 tourism_card_2 tourism_card_3 tourism_card_4 tourism_card_5 tourism_card_6 tourism_aviation_1 tourism_aviation_2]
      ),
      "theatre" => Profile.new(
        key: "theatre",
        label: "Jornal de Teatro",
        groups: {
          "Primeira página" => [["Manchete principal", "hero"], ["Escolha do editor", "theatre_editor_pick"]],
          "Em cartaz" => (1..5).map { |n| ["Em cartaz #{n}", "theatre_billboard_#{n}"] },
          "Crítica e entrevistas" => (1..5).map { |n| ["Crítica #{n}", "theatre_review_#{n}"] },
          "Bastidores e agenda" => (1..5).map { |n| ["Bastidores #{n}", "theatre_backstage_#{n}"] }
        },
        automatic_order: %w[hero theatre_editor_pick theatre_billboard_1 theatre_billboard_2 theatre_billboard_3 theatre_billboard_4 theatre_billboard_5 theatre_review_1 theatre_review_2 theatre_review_3 theatre_review_4 theatre_review_5 theatre_backstage_1 theatre_backstage_2 theatre_backstage_3 theatre_backstage_4 theatre_backstage_5]
      ),
      "barra" => Profile.new(
        key: "barra",
        label: "Jornal da Barra",
        groups: {
          "Capa" => [["Manchete principal", "hero"], ["Escolha do editor", "barra_editor_pick"]],
          "Chamadas" => (1..3).map { |n| ["Chamada #{n}", "barra_brief_#{n}"] },
          "Últimas notícias" => (1..6).map { |n| ["Notícia #{n}", "barra_news_#{n}"] },
          "Editorias" => (1..5).map { |n| ["Destaque de editoria #{n}", "barra_section_#{n}"] }
        },
        automatic_order: %w[hero barra_editor_pick barra_brief_1 barra_brief_2 barra_brief_3 barra_news_1 barra_news_2 barra_news_3 barra_news_4 barra_news_5 barra_news_6 barra_section_1 barra_section_2 barra_section_3 barra_section_4 barra_section_5]
      ),
      "icaro" => Profile.new(
        key: "icaro", label: "Revista Ícaro",
        groups: {
          "Capa" => [["Manchete principal", "hero"]],
          "Chamadas" => (1..3).map { |n| ["Chamada #{n}", "icaro_brief_#{n}"] },
          "Inspiração para partir" => (1..6).map { |n| ["Matéria #{n}", "icaro_card_#{n}"] },
          "Aviação na capa" => (1..2).map { |n| ["Aviação #{n}", "icaro_aviation_#{n}"] }
        }.merge(ICARO_SECTIONS.to_h { |slug, label| ["Página: #{label}", icaro_section_slots(slug).each_with_index.map { |key, i| ["#{label} #{i + 1}", key] }] }),
        automatic_order: %w[hero icaro_brief_1 icaro_brief_2 icaro_brief_3 icaro_card_1 icaro_card_2 icaro_card_3 icaro_card_4 icaro_card_5 icaro_card_6]
      ),
      "gastronomy" => Profile.new(
        key: "gastronomy",
        label: "Revista de Gastronomia",
        groups: {
          "Destaques" => [["Manchete principal", "hero"], ["Escolha do editor", "editor_pick"]],
          "Novidades" => (1..6).map { |n| ["Card de novidades #{n}", "fresh_#{n}"] },
          "Agora" => (1..3).map { |n| ["Chamada do ticker #{n}", "breaking_#{n}"] },
          "Mais lidas" => (1..5).map { |n| ["Item mais lido #{n}", "popular_#{n}"] }
        },
        automatic_order: %w[hero editor_pick fresh_1 fresh_2 fresh_3 fresh_4 fresh_5 fresh_6 breaking_1 breaking_2 breaking_3 popular_1 popular_2 popular_3 popular_4 popular_5]
      ),
      "cinemagazine" => Profile.new(
        key: "cinemagazine",
        label: "CINEMAGAZINE",
        groups: {
          "Destaque editorial" => [["Matéria principal", "cm_news_lead"]],
          "Assuntos do momento" => (1..3).map { |n| ["Chamada Agora #{n}", "cm_ticker_#{n}"] },
          "Notícias e listas" => (1..6).map { |n| ["Card editorial #{n}", "cm_news_#{n}"] }
        },
        automatic_order: %w[cm_news_lead cm_ticker_1 cm_ticker_2 cm_ticker_3 cm_news_1 cm_news_2 cm_news_3 cm_news_4 cm_news_5 cm_news_6]
      ),
      "cinema_journal" => Profile.new(
        key: "cinema_journal",
        label: "Jornal do Cinema",
        groups: {
          "Primeira página" => [["Manchete principal", "jc_lead"], ["Destaque secundário 1", "jc_secondary_1"], ["Destaque secundário 2", "jc_secondary_2"]],
          "Em pauta" => (1..5).map { |n| ["Nota em pauta #{n}", "jc_brief_#{n}"] },
          "Crítica" => (1..5).map { |n| ["Crítica #{n}", "jc_critique_#{n}"] },
          "Ensaios" => (1..4).map { |n| ["Ensaio #{n}", "jc_essay_#{n}"] },
          "Festivais e entrevistas" => (1..4).map { |n| ["Card #{n}", "jc_festival_#{n}"] }
        },
        automatic_order: %w[jc_lead jc_secondary_1 jc_secondary_2 jc_brief_1 jc_brief_2 jc_brief_3 jc_brief_4 jc_brief_5 jc_critique_1 jc_critique_2 jc_critique_3 jc_critique_4 jc_critique_5 jc_essay_1 jc_essay_2 jc_essay_3 jc_essay_4 jc_festival_1 jc_festival_2 jc_festival_3 jc_festival_4]
      )
    }.freeze

    def self.for(site)
      PROFILES.fetch(site.layout_profile, PROFILES["gastronomy"])
    end

    def self.all_slot_keys
      PROFILES.values.flat_map { |profile| profile.groups.values.flatten(1).map(&:last) }.uniq
    end

    def self.label_for(site, slot_key)
      self.for(site).groups.values.flatten(1).to_h { |label, key| [key, label] }[slot_key]
    end
  end
end
