# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding area", type: :request do
  it "POST /admin/onboarding/seed_taxonomy invokes both seeders and the rebuild for the current user, then redirects" do
    user = create(:user)
    sign_in user
    allow(Seeders::Categories).to receive(:call)
    allow(Seeders::MerchantRules).to receive(:call)
    allow(Enrichment::TransactionEnricher).to receive(:rebuild!)

    post "/admin/onboarding/seed_taxonomy"

    expect(Seeders::Categories).to have_received(:call).with(user)
    expect(Seeders::MerchantRules).to have_received(:call).with(user)
    expect(Enrichment::TransactionEnricher).to have_received(:rebuild!).with(user: user)
    expect(response).to redirect_to(admin_root_path)
    expect(flash[:notice]).to be_present
  end

  it "POST /admin/onboarding/seed_taxonomy honors the Referer header for the redirect" do
    user = create(:user)
    sign_in user
    allow(Seeders::Categories).to receive(:call)
    allow(Seeders::MerchantRules).to receive(:call)
    allow(Enrichment::TransactionEnricher).to receive(:rebuild!)

    post "/admin/onboarding/seed_taxonomy", headers: { "HTTP_REFERER" => "/admin/categories" }

    expect(response).to redirect_to("/admin/categories")
  end

  it "POST /admin/onboarding/seed_taxonomy passes only the current user to the seeders, never a second user" do
    user_a = create(:user)
    create(:user)
    sign_in user_a
    allow(Seeders::Categories).to receive(:call)
    allow(Seeders::MerchantRules).to receive(:call)
    allow(Enrichment::TransactionEnricher).to receive(:rebuild!)

    post "/admin/onboarding/seed_taxonomy"

    expect(Seeders::Categories).to have_received(:call).with(user_a).once
    expect(Seeders::MerchantRules).to have_received(:call).with(user_a).once
    expect(Enrichment::TransactionEnricher).to have_received(:rebuild!).with(user: user_a).once
  end

  it "POST /admin/onboarding/seed_taxonomy redirects an anonymous request to the sign-in page" do
    create(:user)
    post "/admin/onboarding/seed_taxonomy"
    expect(response).to redirect_to(new_user_session_path)
  end
end
