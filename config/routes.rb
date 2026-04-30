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

    resources :bank_transactions, only: [ :index, :show ] do
      resource :enrichment, only: [ :update ], controller: "transaction_enrichments"
    end

    resources :cash_transactions

    resources :categories, except: [ :show ] do
      member do
        post :archive
        post :unarchive
      end
    end

    resources :merchants do
      member do
        post :archive
        post :unarchive
        post :approve
      end
      resources :merchant_rules, only: [ :create, :update, :destroy ]
    end

    # LLM enrichment: dashboard (index/create) + per-run live progress (show).
    resources :llm_enrichments, only: [ :index, :show, :create ]

    # Visualization of the entire enrichment pipeline: rules in execution
    # order + payment-method fallback map. Read-only, debugging aid.
    get "matching_engine", to: "matching_engine#show"

    # Each OperationRun kind gets its own admin surface — the underlying
    # OperationRun model is shared, but the UI is concern-specific.
    resources :transaction_syncs, only: [ :index, :show, :new, :create ]

    namespace :settings do
      get "/", to: redirect("/admin/settings/tpp_credentials"), as: :root

      resource :preferences, only: %i[edit update]

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
