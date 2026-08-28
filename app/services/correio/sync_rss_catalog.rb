module Correio
  class SyncRssCatalog
    BASE_URL = "https://www.correiodamanha.com.br".freeze
    CHANNELS = [
      { name: "Últimas notícias", path: nil, keywords: "últimas notícias, correio da manhã" },
      { name: "Opinião", path: "opiniao", keywords: "opinião, editorial, análise" },
      { name: "Política", path: "politica", keywords: "política, governo, congresso, eleições" },
      { name: "Economia", path: "economia", keywords: "economia, mercado, negócios, finanças" },
      { name: "Justiça", path: "economia/justica", keywords: "justiça, judiciário, tribunais" },
      { name: "Cultura", path: "cultura", keywords: "cultura, artes, cinema, música, literatura" },
      { name: "Esportes", path: "esporte/esportes", keywords: "esportes, futebol, campeonatos" },
      { name: "Mundo", path: "mundo", keywords: "mundo, internacional, diplomacia" },
      { name: "Distrito Federal", path: "nacional/distrito-federal", keywords: "distrito federal, brasília, df" },
      { name: "Estado de São Paulo", path: "estado-de-sao-paulo", keywords: "estado de são paulo, sp" },
      { name: "São Paulo", path: "nacional/sao-paulo", keywords: "são paulo, capital paulista" },
      { name: "Estado do Rio", path: "estado-do-rio", keywords: "estado do rio, rio de janeiro" },
      { name: "Rio de Janeiro", path: "rio-de-janeiro", keywords: "rio de janeiro, cidade do rio" }
    ].freeze

    Result = Data.define(:feeds_created, :feeds_updated, :topics_created, :topics_updated)

    def self.call
      new.call
    end

    def call
      counters = Hash.new(0)

      ApplicationRecord.transaction do
        CHANNELS.each do |channel|
          sync_feed(channel, counters)
          sync_topic(channel, counters)
        end
      end

      Result.new(
        feeds_created: counters[:feeds_created],
        feeds_updated: counters[:feeds_updated],
        topics_created: counters[:topics_created],
        topics_updated: counters[:topics_updated]
      )
    end

    private

    def sync_feed(channel, counters)
      url = rss_url(channel[:path])
      feed = Feed.find_or_initialize_by(url: url)
      created = feed.new_record?
      feed.assign_attributes(name: "Correio da Manhã — #{channel[:name]}", active: true)
      feed.save!
      counters[created ? :feeds_created : :feeds_updated] += 1
    end

    def sync_topic(channel, counters)
      name = "Correio — #{channel[:name]}"
      topic = Topic.find_or_initialize_by(name: name)
      created = topic.new_record?
      topic.assign_attributes(
        keywords: channel[:keywords],
        match_mode: "any",
        search_mode: "rss",
        active: true
      )
      topic.save!
      counters[created ? :topics_created : :topics_updated] += 1
    end

    def rss_url(path)
      [BASE_URL, path, "sitemap-rss.xml"].compact.join("/")
    end
  end
end
