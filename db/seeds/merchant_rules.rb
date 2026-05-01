# frozen_string_literal: true

# Apply the baseline merchant rule set to every existing user. The actual
# definitions + logic live in `Seeders::MerchantRules`
# (app/services/seeders/merchant_rules.rb) so it can be called explicitly
# from elsewhere (registration controller, rake tasks, console) without
# re-running the loop.

User.find_each do |user|
  Seeders::MerchantRules.call(user)
  Rails.logger.info "Seeded merchants/rules for #{user.email}: " \
                    "#{user.merchants.where(source: 'system').count} merchants, " \
                    "#{user.merchant_rules.where(source: 'system').count} rules"
end
