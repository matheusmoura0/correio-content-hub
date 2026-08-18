module Api
  module V1
    class ArticlesController < ActionController::API
      def index
        site = Site.find(params[:site_id])
        articles = site.site_articles
          .includes(article: :feed)
          .where(status: "published")
          .order(published_at: :desc)

        render json: articles.map { |item| serialize(item.article, item) }
      end

      def show
        article = Article.find(params[:id])
        render json: serialize(article, nil)
      end

      private

      def serialize(article, distribution)
        {
          id: article.id,
          title: article.title,
          description: article.description,
          content: article.content,
          image_url: article.image_url,
          author: article.author,
          source_url: article.source_url,
          published_at: distribution&.published_at || article.published_at,
          category: distribution&.category&.slug,
          source: article.feed.name
        }
      end
    end
  end
end
