# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

if Rails.env.development?
  admin = User.find_or_initialize_by(email: "maciek@example.com")
  admin.name = "John Doe"
  admin.password = "password"
  admin.password_confirmation = "password"
  admin.save!

  Rails.logger.info "Seeded admin user: #{admin.email} / password"
end
