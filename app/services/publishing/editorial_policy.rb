module Publishing
  class EditorialPolicy
    DEFAULT_TERMS = {
      "tourism" => "turismo, viagem, viagens, turista, turistas, hotel, hotéis, hotelaria, hospedagem, aviação, aeroporto, aeroportos, companhia aérea, destinos turísticos, cruzeiro, cruzeiros",
      "icaro" => "turismo, viagem, viagens, hotel, hotéis, hotelaria, hospedagem, aviação, aeroporto, aeroportos, companhia aérea, destinos turísticos, cruzeiro, cruzeiros",
      "theatre" => "teatro, teatral, teatrais, dramaturgia, dramaturgo, dramaturga, espetáculo teatral, espetáculos teatrais, peça teatral, peças teatrais, artes cênicas",
      "gastronomy" => "gastronomia, gastronômico, gastronômica, culinária, restaurante, restaurantes, receita culinária, receitas culinárias, chef, chefs, vinho, vinhos, cozinha, cerveja, cervejas",
      "cinemagazine" => "cinema, filme, filmes, cineasta, cineastas, streaming, série, séries, audiovisual, bilheteria, oscar, trailer, trailers",
      "cinema_journal" => "cinema, filme, filmes, cineasta, cineastas, audiovisual, bilheteria, oscar, festival de cinema",
      "barra" => "barra da tijuca, recreio dos bandeirantes, jacarepaguá, jardim oceânico, vargem grande, vargem pequena"
    }.freeze
    ACCENTED = "áàâãäéèêëíìîïóòôõöúùûüç".freeze
    ASCII = "aaaaaeeeeiiiiooooouuuuc".freeze

    def self.default_terms(site)
      DEFAULT_TERMS.fetch(site.layout_profile, "")
    end

    def self.scope(site, relation = Article.all)
      new(site).scope(relation)
    end

    def initialize(site)
      @site = site
    end

    def scope(relation)
      return relation.none if terms.empty?

      # Match editorial evidence, not arbitrary mentions deep in the article body.
      text = "concat_ws(' ', articles.title, articles.description, " \
        "(SELECT CASE WHEN feeds.url LIKE 'https://hub.cm.com.br/origens/%' THEN '' " \
        "ELSE concat_ws(' ', articles.source_url, feeds.name, categories.name, feeds.url) END FROM feeds " \
        "LEFT JOIN categories ON categories.id = feeds.category_id WHERE feeds.id = articles.feed_id))"
      normalized = "translate(lower(#{text}), '#{ACCENTED}', '#{ASCII}')"
      specific_terms = terms
      clauses = []
      bindings = {}
      if @site.layout_profile.in?(%w[cinemagazine cinema_journal])
        specific_terms = terms - %w[serie series oscar]
        # Bare "series" also describes crimes and sports; require screen-related evidence.
        editorial_text = "translate(lower(concat_ws(' ', articles.title, articles.description)), '#{ACCENTED}', '#{ASCII}')"
        if terms.intersect?(%w[serie series])
          clauses << "(#{editorial_text} ~ :series AND #{editorial_text} ~ :screen)"
          bindings[:series] = '\\m(serie|series)\\M'
          bindings[:screen] = '\\m(streaming|netflix|hbo|disney|televisao|televisiva|televisivas|televisivo|episodio|episodios|temporada|temporadas|apple tv|prime video)\\M'
        end
        if terms.include?("oscar")
          clauses << "(#{editorial_text} ~ :oscar AND #{editorial_text} ~ :award)"
          bindings[:oscar] = '\\moscar\\M'
          bindings[:award] = '\\m(cinema|filme|filmes|cineasta|hollywood|premio|premios|premiacao|indicacao|indicacoes|ator|atriz|diretor|diretora|roteiro)\\M'
        end
      end
      if specific_terms.any?
        clauses << "#{normalized} ~ :terms"
        bindings[:terms] = "\\m(#{specific_terms.map { |term| Regexp.escape(term) }.join('|')})\\M"
      end
      relation.where(clauses.map { |clause| "(#{clause})" }.join(" OR "), bindings)
    end

    def eligible?(article)
      scope(Article.where(id: article.id)).exists?
    end

    def validate!(article)
      return if eligible?(article)

      article.errors.add(:base, "O assunto da matéria não corresponde à linha editorial de #{@site.name}.")
      raise ActiveRecord::RecordInvalid, article
    end

    private

    def terms
      @terms ||= @site.editorial_keywords.to_s.split(/[\n,;]/).map do |term|
        term.strip.downcase.tr(ACCENTED, ASCII)
      end.reject(&:blank?).uniq
    end
  end
end
