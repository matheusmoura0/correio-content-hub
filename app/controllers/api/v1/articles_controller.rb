module Api
  module V1
    class ArticlesController < ActionController::API
      after_action :allow_publication_sites
      after_action :disable_cache

      def index
        site = params[:site_id].present? ? Site.find(params[:site_id]) : Site.find_by!(domain: params[:domain])
        articles = site.site_articles.joins(:article).includes(:category, article: :feed)
          .where(status: "published")
          .order(Arel.sql("CASE placement WHEN 'hero' THEN 0 WHEN 'editor_pick' THEN 1 ELSE 2 END"), :position, published_at: :desc)
        render json: articles.map { |item| serialize(item.article, item) }
      end

      def show
        article = Article.includes(:feed, site_articles: :category).joins(:site_articles)
          .where(site_articles: { status: "published" }).distinct.find(params[:id])
        gastronomy = Site.find_by(domain: "revistadegastronomia.com.br")
        distribution = article.site_articles.find { |item| item.site_id == gastronomy&.id && item.status == "published" } ||
          article.site_articles.find { |item| item.status == "published" }
        render json: serialize(article, distribution)
      end

      private

      def serialize(article, distribution)
        publisher = article.feed.publisher_name
        publisher_url = article.feed.publisher_url

        {
          id: article.id,
          title: distribution&.display_title.presence || article.rewritten_title.presence || article.title,
          description: article.description,
          content: article.rewritten_content.presence || article.content,
          image_url: article.image_url,
          image_optional: article.image_optional?,
          author: article.author,
          source_url: article.source_url,
          canonical_url: article.source_url,
          published_at: distribution&.published_at || article.published_at,
          updated_at: [article.updated_at, distribution&.updated_at].compact.max,
          category: distribution&.category&.slug,
          placement: distribution&.placement || "latest",
          slot: distribution&.slot_key,
          slot_label: distribution&.slot_label,
          assignment_mode: distribution&.assignment_mode || "automatic",
          image_focus_x: distribution&.image_focus_x || 50,
          image_focus_y: distribution&.image_focus_y || 50,
          image_zoom: (distribution&.image_zoom || 1).to_f,
          position: distribution&.position || 0,
          source: article.feed.name,
          publisher: publisher,
          publisher_url: publisher_url,
          credit: "Publicado originalmente por #{publisher}",
          attribution: {
            name: publisher,
            url: publisher_url,
            canonical_url: article.source_url,
            required: true
          },
          image_credit: article.image_credit,
          image_source_url: article.image_source_url,
          image_license: article.image_license,
          image_rights_confirmed: article.licensed_image_ready?
        }
      end

      def disable_cache
        response.set_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        response.set_header("Pragma", "no-cache")
        response.set_header("Expires", "0")
      end

      def allow_publication_sites
        allowed = Site.where(active: true).pluck(:allowed_origins).flat_map do |origins|
          origins.to_s.lines.map(&:strip)
        end.reject(&:blank?).uniq
        origin = request.headers["Origin"]
        response.set_header("Access-Control-Allow-Origin", origin) if allowed.include?(origin)
        response.set_header("Vary", "Origin")
      end
    end
  end
end
