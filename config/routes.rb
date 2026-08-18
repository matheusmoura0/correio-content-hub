Rails.application.routes.draw do
  devise_for :users

  root "dashboard#index"

  resources :sites, except: :show
  resources :categories, except: :show
  resources :feeds, except: :show do
    post :import, on: :member, action: :import_feed
  end
  resources :articles, only: %i[index show update]

  namespace :api do
    namespace :v1 do
      get "sites/:site_id/articles", to: "articles#index"
      get "articles/:id", to: "articles#show"
    end
  end
end
