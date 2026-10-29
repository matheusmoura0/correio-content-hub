Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: :registrations

  root "products#index"
  get "radar", to: "dashboard#index", as: :radar
  get "produtos", to: "products#index", as: :products
  get "produtos/:publication_key", to: "products#show", as: :product
  post "produtos/:publication_key/retirar/:distribution_id", to: "products#unpublish", as: :unpublish_product

  resources :sites, except: :show
  resources :editorial_editions, only: %i[index show], path: "edicoes" do
    post :prepare, on: :collection
    post :approve, on: :member
    post :reject, on: :member
  end
  resources :categories, except: :show
  get "publicacoes/:publication_key", to: "publications#show", as: :publication
  post "publicacoes/:publication_key/popular", to: "publications#populate", as: :populate_publication
  post "publicacoes/:publication_key/posicionar", to: "publications#assign", as: :assign_publication
  post "publicacoes/:publication_key/lote", to: "publications#bulk", as: :bulk_publication
  post "publicacoes/:publication_key/limpar", to: "publications#clear", as: :clear_publication
  post "feeds/sincronizar-correio", to: "correio_rss_catalog#create", as: :sync_correio_rss_catalog
  resources :feeds, except: :show do
    post :import, on: :member, action: :import_feed
  end
  resources :reporter_articles, only: %i[new create edit update], path: "minhas-materias"
  resources :articles, only: %i[index show update] do
    delete :bulk_delete, on: :collection, action: :destroy_bulk, as: :destroy_bulk
    patch :publish_to_gastronomy, on: :member
    patch :unpublish_from_gastronomy, on: :member
  end
  resources :topics, except: :show do
    post :run, on: :member
  end
  resources :users, except: :show
  resources :activity_logs, only: :index, path: "atividades"
  get "metricas", to: "analytics#index", as: :analytics
  resource :analytics_email_schedule, only: %i[show update], path: "metricas/envio-semanal" do
    post :preview
    post :send_now
    post :add_recipient
    delete :remove_recipient
  end
  resource :analytics_share, only: %i[create update destroy], path: "metricas/compartilhamento"
  get "audiencia/:token", to: "public_analytics#show", as: :public_analytics,
    constraints: { token: /[A-Za-z0-9]{32}/ }, defaults: { format: :html }
  get "audiencia/:token/exportar.pdf", to: "public_analytics#export", as: :export_public_analytics,
    constraints: { token: /[A-Za-z0-9]{32}/ }, defaults: { format: :pdf }
  get "metricas/exportar.:format", to: "analytics#export", as: :export_analytics,
    constraints: { format: /csv|json|pdf/ }
  post "presenca", to: "presence#update", as: :presence
  post "articles/:id/rewrite", to: "article_rewrites#create", as: :rewrite_article

  namespace :api do
    namespace :v1 do
      get "sites/by-domain/articles", to: "articles#index"
      get "sites/:site_id/articles", to: "articles#index"
      get "articles/:id", to: "articles#show"
      get "cinema/home", to: "cinema#home"
      get "cinema/movies/:id", to: "cinema#movie"
      get "cinema/tv/:id", to: "cinema#tv"
      post "analytics/events", to: "analytics_events#create"
    end
  end
end
