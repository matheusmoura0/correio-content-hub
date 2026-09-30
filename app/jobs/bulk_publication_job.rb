class BulkPublicationJob < ApplicationJob
  queue_as :default

  def perform(article_id:, site_id:, action:, user_id:, instructions: nil, category_id: nil)
    article = Article.find(article_id)
    site = Site.find(site_id)
    category = site.categories.find_by(id: category_id)

    if action == "rewrite_publish"
      result = Ai::RewriteArticle.call(article, instructions:)
      article.update!(
        rewritten_title: result.fetch("title"),
        rewritten_content: result.fetch("content"),
        rewrite_instructions: instructions,
        rewritten_at: Time.current,
        rewritten_by_id: user_id,
        status: "reviewing"
      )
    end

    case action
    when "publish", "rewrite_publish"
      Publishing::PublishArticle.call(article:, site:, category:, assignment_mode: "automatic")
    when "unpublish"
      article.site_articles.find_by(site:)&.update!(status: "draft", published_at: nil, slot_key: nil)
    end
  rescue StandardError => error
    Rails.logger.error("Falha no lote para matéria #{article_id}: #{error.class}: #{error.message}")
    raise
  end
end
