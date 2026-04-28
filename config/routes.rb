require "sidekiq/web"

Rails.application.routes.draw do
  devise_for :users,
    path: "admin",
    skip: [ :registrations ],
    controllers: {
      sessions: "admin/sessions",
      passwords: "admin/passwords"
    }

  mount Sidekiq::Web => "/sidekiq"

  get "up" => "rails/health#show", as: :rails_health_check

  # OAuth-like callback from bank after PSU authorizes.
  # Path must match the redirect_url registered with the provider (Enable Banking).
  get "/callback", to: "oauth_callbacks#enable_banking", as: :oauth_callback

  if Rails.env.development?
    namespace :admin do
      get  "debug", to: "debug#index"
      get  "debug/runtime_error"
      get  "debug/zero_division"
      get  "debug/argument_error"
      get  "debug/nested_error"
      post "debug/enqueue_failing_job"
    end
  end

  namespace :admin do
    root "dashboard#index"
    get "styleguide", to: "styleguide#index"

    resources :versions, only: [ :index, :show ]

    namespace :settings do
      get "/", to: redirect("/admin/settings/tpp_credentials"), as: :root

      resources :tpp_credentials do
        member do
          post :test_connection
          post :make_primary
        end
      end

      resources :bank_connections, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
        member do
          post :refresh
          post :reauth
        end
      end

      resources :bank_accounts, only: [ :index, :show ] do
        member do
          post :refresh_details
          post :refresh_balances
        end
      end
    end
  end

  root to: redirect("/admin")
end
