# frozen_string_literal: true

# Apply the baseline taxonomy to every existing user. The actual data +
# logic live in `Seeders::Categories` (app/services/seeders/categories.rb)
# so it can be called explicitly from elsewhere (registration controller,
# rake tasks, console) without re-running the loop.

User.find_each do |user|
  Seeders::Categories.call(user)
  Rails.logger.info "Seeded #{user.categories.count} categories for #{user.email}"
end
