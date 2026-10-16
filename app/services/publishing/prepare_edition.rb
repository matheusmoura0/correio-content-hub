module Publishing
  class PrepareEdition
    CATEGORY_TERMS = {
      "aviacao" => %w[aviacao aeroporto aeroportos aerea aereas],
      "mobilidade" => %w[aviacao aeroporto aeroportos aerea aereas],
      "hotelaria" => %w[hotel hoteis resort resorts pousada pousadas],
      "hospedagem" => %w[hotel hoteis resort resorts pousada pousadas],
      "gastronomia" => %w[gastronomia restaurante restaurantes culinaria chef],
      "sabores" => %w[gastronomia restaurante restaurantes culinaria chef],
      "bebidas" => %w[vinho vinhos cerveja cervejas bebida bebidas],
      "restaurantes" => %w[restaurante restaurantes chef chefs],
      "receitas" => %w[receita receitas ingredientes preparo],
      "streaming" => %w[streaming netflix disney hbo prime],
      "series" => %w[serie series episodio episodios temporada temporadas],
      "entrevistas" => %w[entrevista entrevistas],
      "festivais" => %w[festival festivais cannes berlinale],
      "critica" => %w[critica resenha],
      "roteiros" => %w[roteiro roteiros itinerario itinerarios],
      "destinos" => %w[destino destinos turismo viagem viagens],
      "negocios" => %w[negocios conferencia congresso convencao]
    }.freeze

    def self.ready_candidate?(article)
      article.status != "ignored" && article.publication_ready? &&
        ActionController::Base.helpers.strip_tags(article.rewritten_content.presence || article.content.to_s).strip.length >= 150
    end

    def self.call(site)
      site.with_lock do
        next unless site.publication_destination?
        now = Time.current
        cutoff = now - [ENV.fetch("EDITORIAL_MAX_AGE_DAYS", "7").to_i, 1].max.days
        pending = EditorialEdition.find_by(site:, status: "ready")
        if pending
          changed = !pending.items.pending.exists? || pending.page_digest != EditorialEdition.page_digest(site) || pending.items.pending.includes(:article).any? do |item|
            date = item.article.published_at || item.article.created_at
            item.article_digest != EditorialEdition.article_digest(item.article) || !ready_candidate?(item.article) || !date.between?(cutoff, now)
          end
          next pending unless changed

          pending.items.pending.update_all(decision: "skipped", updated_at: Time.current)
          pending.update!(status: "expired")
        end

        profile = SiteProfile.for(site)
        occupied = site.site_articles.where(status: "published", assignment_mode: "manual").pluck(:slot_key)
        slots = profile.automatic_order - occupied
        next if slots.empty?
        published_ids = site.site_articles.where(status: "published").select(:article_id)
        rejected_ids = EditorialEditionItem.joins(:editorial_edition)
          .where(editorial_editions: { site_id: site.id }, decision: "rejected").select(:article_id)
        candidates = EditorialPolicy.scope(site).where.not(id: published_ids)
          .where.not(id: rejected_ids)
          .where.not(status: "ignored").includes(:feed, :site_articles)
          .where("COALESCE(articles.published_at, articles.created_at) BETWEEN ? AND ?", cutoff, now)
          .order(published_at: :desc, created_at: :desc, id: :desc)
        candidates = candidates.limit([slots.size * 8, 100].max).select { |article| ready_candidate?(article) }
        assignments = slots.filter_map do |slot|
          article = if slot.include?("aviation")
            candidates.find do |candidate|
              text = ActiveSupport::Inflector.transliterate([candidate.title, candidate.description, candidate.feed.name].join(" ")).downcase
              text.match?(/\b(aviacao|aeroporto|aeroportos|aerea|aereas)\b/)
            end
          else
            candidates.first
          end
          next unless article

          candidates.delete(article)
          [article, slot]
        end
        next if assignments.empty?

        edition = EditorialEdition.create!(site:, page_digest: EditorialEdition.page_digest(site))
        categories = site.categories.order(:name).to_a
        assignments.each do |article, slot|
          own_category = article.site_articles.find { |item| item.site_id == site.id }&.category
          text = ActiveSupport::Inflector.transliterate([article.title, article.description].join(" ")).downcase
          category = own_category || categories.find do |item|
            terms = CATEGORY_TERMS.fetch(item.slug, [ActiveSupport::Inflector.transliterate(item.name).downcase])
            terms.any? { |term| text.match?(/\b#{Regexp.escape(term)}\b/) }
          end
          category ||= categories.find { |item| item.slug == "noticias" }
          edition.items.create!(article:, category:, slot_key: slot,
            title: article.rewritten_title.presence || article.title,
            article_digest: EditorialEdition.article_digest(article))
        end
        edition
      end
    end
  end
end
