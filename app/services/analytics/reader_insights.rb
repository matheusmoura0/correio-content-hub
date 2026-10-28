module Analytics
  class ReaderInsights
    MIN_READERS = 5
    CHANNELS = { "direct_or_unknown" => "Direto ou desconhecido", "organic_search" => "Busca orgânica",
      "organic_social" => "Redes sociais", "email" => "E-mail", "paid" => "Campanha paga",
      "referral" => "Referência", "internal" => "Navegação interna", "campaign" => "Campanha" }.freeze
    PLACEMENTS = { "header" => "Cabeçalho", "footer" => "Rodapé", "navigation" => "Navegação",
      "article_body" => "Corpo da matéria", "related" => "Matérias relacionadas", "homepage_lead" => "Destaque da capa",
      "homepage_grid" => "Grade da capa", "share" => "Compartilhamento", "other" => "Outros" }.freeze
    DEVICES = { "mobile" => "Celular", "desktop" => "Desktop", "tablet" => "Tablet" }.freeze
    COUNTRIES = { "BR" => "Brasil", "US" => "Estados Unidos", "PT" => "Portugal", "AR" => "Argentina",
      "GB" => "Reino Unido", "ES" => "Espanha", "FR" => "França", "DE" => "Alemanha" }.freeze

    def initialize(events)
      @all_events = events
      @events = events.where("metadata <> '{}'::jsonb")
      @views = @events.where(event_type: "page_view")
      @clicks = @events.where(event_type: "click")
    end

    def coverage
      @coverage ||= begin
        total = @all_events.where(event_type: "page_view").count
        known = @views.count
        { total: total, known: known, percent: total.positive? ? (known * 100.0 / total).round(1) : 0,
          clicks: @clicks.count, since: @events.minimum(:occurred_at) }
      end
    end

    def breakdowns
      @breakdowns ||= {
        countries: groups(@views.where("metadata->>'geo_source' = 'dbip_city_lite'"), "country_code", COUNTRIES),
        regions: groups(@views.where("metadata->>'region' IS NOT NULL"), "concat_ws(' · ', metadata->>'region', country_code)"),
        cities: groups(@views.where("metadata->>'city' IS NOT NULL"), "concat_ws(' · ', metadata->>'city', metadata->>'region', country_code)"),
        sources: groups(@views.where("metadata->>'traffic_source' IS NOT NULL"), "jsonb_build_array(metadata->>'traffic_source', metadata->>'traffic_channel')::text") { |key|
          source, channel = JSON.parse(key)
          [source == "direct" ? nil : source, CHANNELS[channel]].compact.join(" · ")
        },
        campaigns: groups(@views.where("metadata->>'utm_campaign' IS NOT NULL"), "concat_ws(' · ', metadata->>'utm_campaign', metadata->>'utm_source')"),
        devices: groups(@views, "device_type", DEVICES),
        browsers: groups(@views, "metadata->>'browser'"),
        systems: groups(@views, "metadata->>'operating_system'"),
        timezones: groups(@views, "metadata->>'time_zone'"),
        placements: groups(@clicks, "metadata->>'click_placement'", PLACEMENTS)
      }
    end

    def hourly
      @hourly ||= begin
        expression = "EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::integer"
        values = @events.where(event_type: %w[page_view click]).group(Arel.sql(expression), :event_type)
          .pluck(Arel.sql(expression), :event_type, Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT visitor_hash)"))
        lookup = values.to_h { |hour, type, count, readers| [[hour, type], readers >= MIN_READERS ? count : nil] }
        (0..23).map { |hour| { hour: hour, views: lookup.fetch([hour, "page_view"], 0), clicks: lookup.fetch([hour, "click"], 0) } }
      end
    end

    def reading
      @reading ||= begin
        ids = @views.where("metadata->>'tracking_version' = '2'").where.not(page_view_uuid: nil).select(:page_view_uuid)
        active = numeric("active_seconds", 86400)
        depth = numeric("scroll_depth", 100)
        pages = @events.where(page_view_uuid: ids).group(:page_view_uuid).select(
          Arel.sql("MAX(#{active}) AS active, MAX(#{depth}) AS depth, MAX(visitor_hash) AS reader"))
        connection = ActiveRecord::Base.connection
        stats = connection.select_one("SELECT COUNT(*) AS pages, COUNT(DISTINCT reader) AS readers,
          COUNT(DISTINCT reader) FILTER (WHERE active > 0) AS active_readers,
          percentile_cont(0.5) WITHIN GROUP (ORDER BY active) FILTER (WHERE active > 0) AS active_median,
          COUNT(*) FILTER (WHERE depth >= 75) AS deep_pages FROM (#{pages.to_sql}) AS reader_pages")
        count = stats["pages"].to_i
        click_readers = @clicks.where.not(page_elapsed_ms: nil).distinct.count(:visitor_hash)
        delay = if click_readers >= MIN_READERS
          @clicks.where.not(page_elapsed_ms: nil).pick(Arel.sql("percentile_cont(0.5) WITHIN GROUP (ORDER BY page_elapsed_ms)"))
        end
        { pages: count,
          active_seconds: stats["active_readers"].to_i >= MIN_READERS ? stats["active_median"].to_f.round : nil,
          scroll_75_percent: stats["readers"].to_i >= MIN_READERS && count.positive? ? (stats["deep_pages"].to_i * 100.0 / count).round(1) : nil,
          click_delay_seconds: delay && (delay.to_f / 1000).round(1) }
      end
    end

    def notes
      ["Dados de público disponíveis somente para tráfego com os novos metadados; não há preenchimento retroativo.",
        "Grupos com menos de #{MIN_READERS} identificadores diários distintos não são exibidos. Eles não representam pessoas únicas no período.",
        "Horários agregados pelo recebimento no servidor, no fuso de Brasília (America/Sao_Paulo). Não indicam o melhor horário para publicar por si só.",
        "Leitura ativa é uma estimativa. Rolagem não comprova leitura concluída; visualizações abertas podem ainda não ter enviado dados.",
        "Geolocalização aproximada por DB-IP City Lite (CC BY 4.0): https://db-ip.com. VPNs e redes móveis podem alterar a estimativa."]
    end

    private

    def groups(scope, expression, labels = {})
      scope.where("#{expression} IS NOT NULL AND #{expression} <> ''").group(Arel.sql(expression))
        .having("COUNT(DISTINCT visitor_hash) >= ?", MIN_READERS)
        .order(Arel.sql("COUNT(*) DESC, #{expression} ASC")).limit(6)
        .pluck(Arel.sql(expression), Arel.sql("COUNT(*)")).map do |key, count|
          label = block_given? ? yield(key) : labels.fetch(key, key)
          { label: label.to_s.first(140), count: count }
        end
    end

    def numeric(key, maximum)
      "CASE WHEN metadata->>'#{key}' ~ '^[0-9]{1,5}$' THEN LEAST((metadata->>'#{key}')::integer, #{maximum}) ELSE 0 END"
    end
  end
end
