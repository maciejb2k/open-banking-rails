# frozen_string_literal: true

module Admin
  # First-run setup — gives an admin a one-click way to load the baseline
  # taxonomy + system merchant rules into their account when categories
  # are missing (fresh registration, dev wipe, or migration recovery).
  #
  # Production registration flow should call `Seeders::Categories.call` and
  # `Seeders::MerchantRules.call` directly during user creation; this
  # controller is the manual escape hatch.
  class OnboardingController < BaseController
    # POST /admin/onboarding/seed_taxonomy
    def seed_taxonomy
      Seeders::Categories.call(current_user)
      Seeders::MerchantRules.call(current_user)
      Enrichment::TransactionEnricher.rebuild!(user: current_user)

      redirect_back_or_to admin_root_path,
                          notice: "Baseline taxonomy loaded — #{current_user.categories.count} categories, #{current_user.merchants.where(source: 'system').count} system merchants. Existing transactions reclassified."
    end
  end
end
