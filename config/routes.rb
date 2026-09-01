Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: :registrations

  root "dashboard#index"

  resources :sites, except: :show
  resources :categories, except: :show
  post "feeds/sincronizar-correio", to: "correio_rss_catalog#create", as: :sync_correio_rss_catalog
  resources :feeds, except: :show do
    post :import, on: :member, action: :import_feed
  end
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
    end
  end
end
