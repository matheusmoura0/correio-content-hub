module Publishing
  class SiteProfile
    Profile = Data.define(:key, :label, :groups, :automatic_order)

    PROFILES = {
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
