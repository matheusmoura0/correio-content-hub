module Api
  module V1
    class ArticlesController < ActionController::API
      after_action :allow_gastronomy_site

      def index
        site = params[:site_id].present? ? Site.find(params[:site_id]) : Site.find_by!(domain: params[:domain])
        articles = site.site_articles.includes(article: :feed).where(status: "published")
          .order(Arel.sql("CASE placement WHEN 'hero' THEN 0 WHEN 'editor_pick' THEN 1 ELSE 2 END"), :position, published_at: :desc)
        render json: articles.map { |item| serialize(item.article, item) }
      end

      def show
        article = Article.find(params[:id])
        render json: serialize(article, nil)
      end

      private

      def serialize(article, distribution)
        { id: article.id, title: article.rewritten_title.presence || article.title,
          description: article.description, content: article.rewritten_content.presence || article.content,
          image_url: article.image_url, author: article.author, source_url: article.source_url,
          published_at: distribution&.published_at || article.published_at,
          category: distribution&.category&.slug, placement: distribution&.placement || "latest",
          position: distribution&.position || 0, source: article.feed.name }
      end

      def allow_gastronomy_site
        allowed = %w[https://revistadegastronomia.com.br https://www.revistadegastronomia.com.br https://revista-de-gastronomia.vercel.app]
        origin = request.headers["Origin"]
        response.set_header("Access-Control-Allow-Origin", origin) if allowed.include?(origin)
        response.set_header("Vary", "Origin")
      end
    end
  end
end
