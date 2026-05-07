# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth smoke", :smoke, type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  it "redirects unauthenticated GET /admin to the sign-in page" do
    User.create!(email: "existing@example.test", password: "Password123!", name: "Existing")
    visit "/admin"
    expect(page).to have_current_path("/admin/sign_in", ignore_query: true)
  end

  it "redirects unauthenticated GET /admin/bank_transactions to the sign-in page" do
    User.create!(email: "existing@example.test", password: "Password123!", name: "Existing")
    visit "/admin/bank_transactions"
    expect(page).to have_current_path("/admin/sign_in", ignore_query: true)
  end

  it "redirects unauthenticated GET /admin/settings/preferences/profile to the sign-in page" do
    User.create!(email: "existing@example.test", password: "Password123!", name: "Existing")
    visit "/admin/settings/preferences/profile"
    expect(page).to have_current_path("/admin/sign_in", ignore_query: true)
  end

  it "renders the first-run setup page when no User exists" do
    expect(User.count).to eq(0)
    visit "/setup"
    expect(page.status_code).to eq(200)
    expect(page).to have_field("user[email]")
  end

  it "redirects /setup to the sign-in page once a User exists" do
    User.create!(email: "existing@example.test", password: "Password123!", name: "Existing")
    visit "/setup"
    expect(page).to have_current_path("/admin/sign_in", ignore_query: true)
  end

  it "renders the sign-in page directly" do
    visit "/admin/sign_in"
    expect(page.status_code).to eq(200)
    expect(page).to have_field("user[email]")
  end

  it "renders the password reset request page" do
    visit "/admin/password/new"
    expect(page.status_code).to eq(200)
    expect(page).to have_field("user[email]")
  end
end
