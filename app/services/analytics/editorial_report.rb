module Analytics
  # Editorial aggregates use half-open periods so boundary events cannot be counted twice.
  class EditorialReport
    DIMENSIONS = { "articles" => :content_key, "authors" => :content_author, "categories" => :content_category }.freeze
    LABELS = { "articles" => "Matérias", "authors" => "Jornalistas", "categories" => "Editorias" }.freeze
    SORTS = %w[views articles clicks engagement_seconds].freeze
    MISSING = "__missing__".freeze
    attr_reader :site, :from, :to, :filters, :dimension, :sort

    def initialize(site:, from:, to:, filters: {}, dimension: "articles", sort: "views")
      @site, @from, @to = site, from, to
      @filters = filters.to_h.symbolize_keys.slice(:author, :category, :article, :q).transform_values { |v| v.to_s.strip }.reject { |_, v| v.blank? }
      @dimension = DIMENSIONS.key?(dimension) ? dimension : "articles"
      @sort = SORTS.include?(sort) ? sort : "views"
    end

    def label
      LABELS.fetch(dimension)
    end

    def previous_from
      from - (to - from)
    end

    def summary(previous: false)
      @summaries ||= {}
      @summaries[previous] ||= aggregate(scope(previous)).first
    end

    def comparison
      summary.to_h { |key, value| [key, change(value, summary(previous: true)[key])] }
    end

    def change(current, previous)
      return nil if previous.to_f.zero?
      ((current.to_f - previous.to_f) * 100 / previous.to_f).round(1)
    end

    def total_rows
      scope.where(event_type: "page_view").group(Arel.sql(group_expression)).count.size
    end

    def rows(limit: 50, offset: 0)
      query = scope.group(Arel.sql(group_expression)).having("SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) > 0")
        .order(Arel.sql("#{sort_expression} DESC, #{group_expression} ASC"))
      query = query.limit(limit).offset(offset) if limit
      result = aggregate(query, grouped: true)
      return result if result.empty?

      keys = result.map { |row| row[:key] }
      prior = aggregate(scope(true).where("#{group_expression} IN (?)", keys).group(Arel.sql(group_expression)), grouped: true).index_by { |r| r[:key] }
      per_article = scope.where(event_type: "page_view").where("#{group_expression} IN (?)", keys)
        .group(Arel.sql(group_expression), :content_key).count
      medians = per_article.group_by { |(group_key, _), _| group_key }.transform_values do |counts|
        sorted = counts.map(&:last).sort
        (sorted[(sorted.length - 1) / 2] + sorted[sorted.length / 2]) / 2.0
      end
      result.each do |row|
        row[:previous_views] = prior.dig(row[:key], :views).to_i
        row[:views_change] = change(row[:views], row[:previous_views])
        row[:median_views] = medians[row[:key]] || 0
      end
    end

    def daily_views
      # The dashboard explicitly uses UTC, matching the ingestion timestamps.
      counts = scope.where(event_type: "page_view").group(Arel.sql("DATE(occurred_at)")).count
      (from.to_date...to.to_date).map { |date| { date: date.iso8601, views: counts.fetch(date, 0) } }
    end

    def devices
      scope.where(event_type: "page_view").group(:device_type).count
    end

    def top_clicks
      scope.where(event_type: "click").where.not(target_url: [nil, ""])
        .group(:target_url).order(Arel.sql("COUNT(*) DESC")).limit(20).count
    end

    def as_json(*)
      { site: { id: site.id, name: site.name }, dimension: dimension, sort: sort,
        period: { from: from.iso8601, to_exclusive: to.iso8601, timezone: "UTC", previous_from: previous_from.iso8601 },
        filters: filters, summary: summary, previous_summary: summary(previous: true), comparison: comparison,
        daily_views: daily_views, rows: rows(limit: nil), notes: notes }
    end

    def notes
      ["Somente matérias com ID e acessos registrados; não é a quantidade total publicada no CMS.",
       "Identificadores de visitantes mudam diariamente; a contagem não representa pessoas únicas no período.",
       "Tempo registrado pela tag legada, sem garantia de atividade contínua. Não representa leitura concluída.",
       "Autoria usa o texto recebido pela tag; assinaturas coletivas e coautorias ainda não são separadas.",
       "Comparação com período anterior de mesma duração. Sem base anterior, a variação é indefinida."]
    end

    private

    def sort_expression
      {
        "views" => "SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END)",
        "articles" => "COUNT(DISTINCT CASE WHEN event_type = 'page_view' THEN content_key END)",
        "clicks" => "SUM(CASE WHEN event_type = 'click' THEN 1 ELSE 0 END)",
        "engagement_seconds" => "SUM(CASE WHEN event_type = 'engagement' THEN value ELSE 0 END)"
      }.fetch(sort)
    end

    def group_expression
      "COALESCE(NULLIF(#{DIMENSIONS.fetch(dimension)}, ''), '#{MISSING}')"
    end

    def scope(previous = false)
      relation = site.analytics_events.where(occurred_at: (previous ? previous_from...from : from...to))
        .where.not(content_key: [nil, ""])
      { author: :content_author, category: :content_category, article: :content_key }.each do |key, column|
        next unless filters[key]
        relation = relation.where(column => (filters[key] == MISSING ? [nil, ""] : filters[key]))
      end
      if filters[:q]
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(filters[:q])}%"
        relation = relation.where("page_title ILIKE :q OR content_key ILIKE :q OR content_author ILIKE :q OR content_category ILIKE :q", q: pattern)
      end
      relation
    end

    def aggregate(relation, grouped: false)
      expressions = []
      expressions += ["#{group_expression} AS group_key", "MAX(page_title)", "MAX(content_author)", "MAX(content_category)"] if grouped
      expressions += [
        "SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) AS views",
        "COUNT(DISTINCT CASE WHEN event_type = 'page_view' THEN visitor_hash END) AS visitors",
        "COUNT(DISTINCT CASE WHEN event_type = 'page_view' THEN content_key END) AS articles",
        "SUM(CASE WHEN event_type = 'click' THEN 1 ELSE 0 END) AS clicks",
        "SUM(CASE WHEN event_type = 'engagement' THEN value ELSE 0 END) AS engagement_seconds"
      ]
      relation.pluck(*expressions.map { |sql| Arel.sql(sql) }).map do |values|
        row = {}
        if grouped
          key, title, author, category = values.shift(4)
          row.merge!(key: key, title: title.presence || key, author: author.presence || "Sem autoria", category: category.presence || "Sem editoria")
          row[:name] = dimension == "articles" ? row[:title] : (key == MISSING ? "Não informado" : key)
        end
        %i[views visitors articles clicks engagement_seconds].zip(values).each { |key, value| row[key] = value.to_i }
        row
      end
    end
  end
end
