# frozen_string_literal: true

FactoryBot.define do
  factory :styleguide_demo do
    name         { "Demo Name" }
    email        { "demo@example.test" }
    category_id  { nil }

    skip_create
  end
end
