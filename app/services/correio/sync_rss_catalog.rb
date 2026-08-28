module Correio
  class SyncRssCatalog
    BASE_URL = "https://www.correiodamanha.com.br".freeze
    CHANNELS = [
      { name: "Últimas notícias", path: nil },
      { name: "Opinião", path: "opiniao" },
      { name: "Política", path: "politica" },
      { name: "Economia", path: "economia" },
      { name: "Justiça", path: "economia/justica" },
      { name: "Cultura", path: "cultura" },
      { name: "Esportes", path: "esporte/esportes" },
      { name: "Mundo", path: "mundo" },
      { name: "Distrito Federal", path: "nacional/distrito-federal" },
      { name: "Estado de São Paulo", path: "estado-de-sao-paulo" },
      { name: "São Paulo", path: "nacional/sao-paulo" },
      { name: "Estado do Rio", path: "estado-do-rio" },
      { name: "Rio de Janeiro", path: "rio-de-janeiro" }
    ].freeze

    Result = Data.define(:feeds_created, :feeds_updated, :legacy_topics_disabled)

    def self.call
      new.call
    end

    def call
      counters = Hash.new(0)

      ApplicationRecord.transaction do
        CHANNELS.each { |channel| sync_feed(channel, counters) }
        counters[:legacy_topics_disabled] = disable_legacy_topics
      end

      Result.new(
        feeds_created: counters[:feeds_created],
        feeds_updated: counters[:feeds_updated],
        legacy_topics_disabled: counters[:legacy_topics_disabled]
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

    def disable_legacy_topics
      names = CHANNELS.map { |channel| "Correio — #{channel[:name]}" }
      Topic.where(name: names, active: true).update_all(active: false, updated_at: Time.current)
    end

    def rss_url(path)
      [BASE_URL, path, "sitemap-rss.xml"].compact.join("/")
    end
  end
end
