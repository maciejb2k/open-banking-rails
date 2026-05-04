require "sidekiq/web"

Rails.application.routes.draw do
  devise_for :users,
    path: "admin",
    skip: [ :registrations ],
    controllers: {
      sessions: "admin/sessions",
      passwords: "admin/passwords"
    }

  authenticate :user do
    mount Sidekiq::Web => "/sidekiq"
  end

  # First-run setup. Empty-instance redirect is enforced in
  # ApplicationController; this route is the destination.
  get  "/setup", to: "setup#new",    as: :setup
  post "/setup", to: "setup#create"

  get "up" => "rails/health#show", as: :rails_health_check

  # OAuth-like callback from bank after PSU authorizes.
  # Path must match the redirect_url registered with the provider (Enable Banking).
  get "/callback", to: "oauth_callbacks#enable_banking", as: :oauth_callback

  get "/api/:version/docs", to: "swagger#index", as: :api_docs, constraints: { version: /v\d+/ }

  match "/mcp", to: "mcp#handle", via: %i[get post delete]

  mount Api => "/"

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
    # Analytics is the entry point - /admin redirects to it. Operations
    # / Classification / Settings are concrete-tool sections; the
    # at-a-glance view is what you want when you land on the app.
    root to: redirect("/admin/analytics")
    get "styleguide", to: "styleguide#index"

    # Manual one-click escape hatch when the taxonomy isn't seeded
    # (fresh signup, dev wipe). Production reg flow should call
    # Seeders::Categories.call directly during user creation.
    post "onboarding/seed_taxonomy", to: "onboarding#seed_taxonomy", as: :onboarding_seed_taxonomy

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

    namespace :analytics do
      root "dashboard#index"
      resources :categories, only: :show, param: :slug
      resources :merchants,  only: :show, param: :slug
    end

    # Visualization of the entire enrichment pipeline: rules in execution
    # order + payment-method fallback map. Read-only, debugging aid.
    get "matching_engine", to: "matching_engine#show"

    # Each OperationRun kind gets its own admin surface - the underlying
    # OperationRun model is shared, but the UI is concern-specific.
    resources :transaction_syncs, only: [ :index, :show, :new, :create ]

    # AISP-provider plumbing (credentials, consents, accounts) lives at the
    # top level alongside merchants/categories/etc. The "Bank Integrations"
    # sidebar group is purely UI - same flat URL convention as every other
    # admin section.
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
      resource :sync_schedule, only: %i[edit update], controller: "sync_schedules"
    end

    resources :bank_accounts, only: [ :index, :show ] do
      member do
        post :refresh_details
        post :refresh_balances
      end
    end

    namespace :settings do
      get "/", to: redirect("/admin/settings/preferences"), as: :root

      # Bare /preferences lands on the first section.
      get "preferences", to: redirect("/admin/settings/preferences/profile"),
                         as: :preferences

      # Each preference section is its own GET (form) + PATCH (save) - keeps
      # params permitted lists cleanly scoped per concern, and lets us add
      # a fourth section without growing one fat controller action.
      scope "preferences", as: :preferences do
        get   "profile",  to: "preferences#profile",         as: :profile
        patch "profile",  to: "preferences#update_profile"
        patch "password", to: "preferences#update_password", as: :password

        get   "app",      to: "preferences#app",             as: :app
        patch "app",      to: "preferences#update_app"

        get   "llm",      to: "preferences#llm",             as: :llm
        patch "llm",      to: "preferences#update_llm"
        post  "llm/test", to: "preferences#test_llm",        as: :test_llm

        # Export/import of user-owned domain data. Lives next to Preferences
        # in the side nav (registry in Admin::BaseHelper#preferences_sections)
        # but its own controller - file upload + bundle cipher don't fit the
        # field-grouped form pattern of PreferencesController.
        get   "data_exchange",        to: "data_exchange#show",   as: :data_exchange
        post  "data_exchange/export", to: "data_exchange#export", as: :data_exchange_export
        post  "data_exchange/import", to: "data_exchange#import", as: :data_exchange_import

        resources :api_tokens, only: %i[index create destroy], controller: "api_tokens"
      end
    end
  end

  root to: redirect("/admin")
end
