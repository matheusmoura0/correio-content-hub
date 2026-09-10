module Analytics
  class Report
    attr_reader :site, :from, :to

    def initialize(site:, from:, to:)
      @site = site
      @from = from
      @to = to
    end

    def summary
      @summary ||= {
        views: page_views.count,
        visitors: page_views.where.not(visitor_hash: [nil, ""]).distinct.count(:visitor_hash),
        clicks: clicks.count,
        ctr: percentage(clicks.count, page_views.count),
        average_engagement: average_engagement
      }
    end

    def daily_views
      counts = page_views.group("DATE(occurred_at)").count
      (from.to_date..to.to_date).map { |date| { date: date, views: counts.fetch(date, 0) } }
    end

    def top_pages(limit: 20)
      rows = page_views.group(:path).order(Arel.sql("COUNT(*) DESC")).limit(limit)
        .pluck(:path, Arel.sql("MAX(page_title)"), Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT visitor_hash)"))
      rows.map { |path, title, views, visitors| { path: path, title: title.presence || path, views: views, visitors: visitors } }
    end

    def top_clicks(limit: 15)
      clicks.where.not(target_url: [nil, ""]).group(:target_url, :target_text)
        .order(Arel.sql("COUNT(*) DESC")).limit(limit).count
        .map { |(url, text), count| { url: url, text: text.presence || url, clicks: count } }
    end

    def top_articles(limit: 20)
      page_views.where.not(content_key: [nil, ""]).group(:content_key)
        .order(Arel.sql("COUNT(*) DESC")).limit(limit)
        .pluck(:content_key, Arel.sql("MAX(page_title)"), Arel.sql("MAX(content_category)"), Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT visitor_hash)"))
        .map { |key, title, category, views, visitors| { key: key, title: title.presence || key, category: category, views: views, visitors: visitors } }
    end

    def referrers(limit: 10)
      direct = 0
      hosts = Hash.new(0)
      page_views.pluck(:referrer).each do |referrer|
        host = URI.parse(referrer.to_s).host.to_s.downcase.sub(/\Awww\./, "")
        if host.blank? || host == site.domain.to_s.sub(/\Awww\./, "")
          direct += 1
        else
          hosts[host] += 1
        end
      rescue URI::InvalidURIError
        direct += 1
      end
      hosts["Direto / interno"] += direct if direct.positive?
      hosts.sort_by { |_host, count| -count }.first(limit).map { |host, count| { source: host, views: count } }
    end

    def devices
      page_views.group(:device_type).count.map do |device, count|
        { device: device.presence || "desconhecido", views: count, share: percentage(count, summary[:views]) }
      end.sort_by { |row| -row[:views] }
    end

    def as_json(*)
      { site: { id: site.id, name: site.name, domain: site.domain }, period: { from: from, to: to },
        summary: summary, daily_views: daily_views, top_pages: top_pages, top_articles: top_articles,
        top_clicks: top_clicks, referrers: referrers, devices: devices }
    end

    private

    def events
      @events ||= site.analytics_events.where(occurred_at: from..to)
    end

    def page_views
      @page_views ||= events.where(event_type: "page_view")
    end

    def clicks
      @clicks ||= events.where(event_type: "click")
    end

    def average_engagement
      values = events.where(event_type: "engagement").where.not(session_hash: [nil, ""])
        .group(:session_hash).sum(:value).values
      return 0 if values.empty?

      (values.sum.to_f / values.size).round
    end

    def percentage(part, total)
      total.to_i.zero? ? 0.0 : ((part.to_f / total) * 100).round(1)
    end
  end
end
