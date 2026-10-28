module Analytics
  # Editorial aggregates use half-open periods so boundary events cannot be counted twice.
  class EditorialReport
    DIMENSIONS = { "articles" => :content_key, "columnists" => :content_author, "authors" => :content_author, "categories" => :content_category }.freeze
    LABELS = { "articles" => "Matérias", "columnists" => "Colunistas", "authors" => "Jornalistas", "categories" => "Editorias" }.freeze
    SORTS = %w[views articles clicks engagement_seconds].freeze
    MISSING = "__missing__".freeze
    attr_reader :site, :from, :to, :filters, :dimension, :sort

    def initialize(site:, from:, to:, filters: {}, dimension: "articles", sort: "views")
      @site, @from, @to = site, from, to
      @filters = filters.to_h.symbolize_keys.slice(:author, :columnist, :category, :article, :q).transform_values { |v| v.to_s.strip }.reject { |_, v| v.blank? }
      @dimension = DIMENSIONS.key?(dimension) ? dimension : "articles"
      @sort = SORTS.include?(sort) ? sort : "views"
    end

    def label
      LABELS.fetch(dimension)
    end

    def columnist_name
      profiles_by_slug[filters[:columnist]]&.name || filters[:columnist]
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
        %i[views articles clicks engagement_seconds].each do |metric|
          row["previous_#{metric}".to_sym] = prior.dig(row[:key], metric).to_i
        end
        row[:views_change] = change(row[:views], row[:previous_views])
        row[:median_views] = medians[row[:key]] || 0
        profile = dimension == "columnists" ? profiles_by_slug[row[:key]] : profiles_by_alias[AuthorIdentity.normalize(row[:author])]
        if profile
          row[:author_image_url] = profile.image_url.presence || row[:author_image_url]
          row[:name] = profile.name if dimension == "columnists"
        end
      end
    end

    def daily_views(previous: false)
      # The dashboard explicitly uses UTC, matching the ingestion timestamps.
      relation = scope(previous).where(event_type: "page_view")
      counts = relation.group(Arel.sql("DATE(occurred_at)")).count
      range_start = previous ? previous_from : from
      range_end = previous ? from : to
      (range_start.to_date...range_end.to_date).map { |date| { date: date.iso8601, views: counts.fetch(date, 0) } }
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
      result = ["Somente matérias com ID e acessos registrados; não é a quantidade total publicada no CMS.",
       "Identificadores de visitantes mudam diariamente; a contagem não representa pessoas únicas no período.",
       "Tempo registrado pela tag legada, sem garantia de atividade contínua. Não representa leitura concluída.",
       "Autoria usa o texto recebido pela tag; assinaturas coletivas e coautorias ainda não são separadas.",
       "Comparação com período anterior de mesma duração. Sem base anterior, a variação é indefinida."]
      if dimension == "columnists" || filters[:columnist]
        result << "Colunistas: somente assinaturas individuais reconhecidas nos perfis oficiais. Prefixo 'Por', caixa e acentos são normalizados; coautorias e assinaturas coletivas ficam em Jornalistas, sem atribuição automática a uma pessoa."
      end
      result
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
      return columnist_expression if dimension == "columnists"

      "COALESCE(NULLIF(#{DIMENSIONS.fetch(dimension)}, ''), '#{MISSING}')"
    end

    def profiles_by_slug
      @profiles_by_slug ||= site.analytics_author_profiles.columnists.order(:slug).index_by(&:slug)
    end

    def profiles_by_alias
      @profiles_by_alias ||= profiles_by_slug.values.each_with_object({}) do |profile, result|
        profile.aliases.each { |name| result[name] = profile }
      end
    end

    def columnist_expression
      @columnist_expression ||= begin
        connection = ActiveRecord::Base.connection
        cases = profiles_by_slug.values.flat_map do |profile|
          profile.aliases.map { |name| "WHEN #{connection.quote(name)} THEN #{connection.quote(profile.slug)}" }
        end
        cases.empty? ? "NULL::text" : "CASE #{AuthorIdentity.sql} #{cases.join(' ')} ELSE NULL END"
      end
    end

    def scope(previous = false)
      relation = site.analytics_events.where(occurred_at: (previous ? previous_from...from : from...to))
        .where.not(content_key: [nil, ""])
      relation = relation.where("#{columnist_expression} IS NOT NULL") if dimension == "columnists"
      if filters[:columnist]
        relation = relation.where("#{columnist_expression} = ?", filters[:columnist])
      end
      { author: :content_author, category: :content_category, article: :content_key }.each do |key, column|
        next unless filters[key]
        relation = relation.where(column => (filters[key] == MISSING ? [nil, ""] : filters[key]))
      end
      if filters[:q]
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(filters[:q])}%"
        names = profiles_by_slug.values.select do |profile|
          ([AuthorIdentity.normalize(profile.name)] + profile.aliases).any? { |name| name.include?(AuthorIdentity.normalize(filters[:q])) }
        end.map(&:slug)
        relation = relation.where("page_title ILIKE ? OR content_key ILIKE ? OR content_author ILIKE ? OR content_category ILIKE ? OR #{columnist_expression} IN (?)", pattern, pattern, pattern, pattern, names)
      end
      relation
    end

    def aggregate(relation, grouped: false)
      expressions = []
      expressions += ["#{group_expression} AS group_key", "MAX(page_title)", "MAX(content_author)", "MAX(content_category)", "MAX(image_url)", "MAX(author_image_url)"] if grouped
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
          key, title, author, category, image_url, author_image_url = values.shift(6)
          row.merge!(key: key, title: title.presence || key, author: author.presence || "Sem autoria",
            category: category.presence || "Sem editoria", image_url: image_url.presence,
            author_image_url: author_image_url.presence)
          row[:name] = dimension == "articles" ? row[:title] : (key == MISSING ? "Não informado" : key)
        end
        %i[views visitors articles clicks engagement_seconds].zip(values).each { |key, value| row[key] = value.to_i }
        row
      end
    end
  end
end
