# frozen_string_literal: true

FactoryBot.define do
  factory :user_hidden_category do
    user
    category { association :category, user: user }
  end
end
