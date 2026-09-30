class ArticleRewritesController < ApplicationController
  def create
    @article = Article.find(params[:id])
    instructions = params[:rewrite_instructions].to_s.strip
    result = Ai::RewriteArticle.call(@article, instructions:)
    @article.update!(
      rewritten_title: result.fetch("title"),
      rewritten_content: result.fetch("content"),
      rewrite_instructions: instructions,
      rewritten_at: Time.current,
      rewritten_by: current_user,
      status: "reviewing"
    )
    redirect_to @article, notice: "Versão reescrita criada. Revise o texto antes de utilizá-lo."
  rescue Ai::RewriteArticle::ConfigurationError, Ai::RewriteArticle::RequestError => error
    redirect_to @article, alert: error.message
  end
end
