require "sidekiq/web"

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"

  get "up" => "rails/health#show", as: :rails_health_check

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
  end

  root to: redirect("/admin")
end
