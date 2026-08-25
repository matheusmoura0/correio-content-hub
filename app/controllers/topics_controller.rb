class TopicsController < ApplicationController
  before_action :set_topic, only: %i[edit update destroy run]

  def index
    @topics = Topic.includes(topic_articles: { article: :feed }).order(created_at: :desc)
  end

  def new
    @topic = Topic.new(match_mode: "any", active: true)
  end

  def create
    @topic = Topic.new(topic_params)
    if @topic.save
      redirect_to topics_path, notice: "Pesquisa criada. Clique em Pescar matérias para buscar resultados."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @topic.update(topic_params)
      redirect_to topics_path, notice: "Pesquisa atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @topic.destroy!
    redirect_to topics_path, notice: "Pesquisa removida."
  end

  def run
    result = Topics::RunSearch.call(@topic)
    message = "Pesca concluída: #{result.matches} nova(s) correspondência(s) e #{result.imported} matéria(s) importada(s)."
    message += " Não foi possível consultar: #{result.feed_errors.join(', ')}." if result.feed_errors.any?
    redirect_to topics_path(anchor: "topic-#{@topic.id}"), notice: message
  end

  private

  def set_topic
    @topic = Topic.find(params[:id])
  end

  def topic_params
    params.require(:topic).permit(:name, :keywords, :match_mode, :active)
  end
end
