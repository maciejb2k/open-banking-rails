# frozen_string_literal: true

module Admin
  # Manual escape hatch when categories are missing (dev wipe, migration
  # recovery). Production registration calls Seeders::Categories /
  # Seeders::MerchantRules directly.
  class OnboardingController < BaseController
    def seed_taxonomy
      Seeders::Categories.call(current_user)
      Seeders::MerchantRules.call(current_user)
      Enrichment::TransactionEnricher.rebuild!(user: current_user)

      redirect_back_or_to admin_root_path,
                          notice: "Baseline taxonomy loaded - #{current_user.categories.count} categories, #{current_user.merchants.where(source: 'system').count} system merchants. Existing transactions reclassified."
    end
  end
end
