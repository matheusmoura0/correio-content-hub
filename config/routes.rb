Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: :registrations

  root "dashboard#index"

  resources :sites, except: :show
  resources :categories, except: :show
  resources :feeds, except: :show do
    post :import, on: :member, action: :import_feed
  end
  resources :articles, only: %i[index show update]
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
    end
  end
end
