# frozen_string_literal: true

require "rails_helper"

RSpec.describe "First-run setup journey", type: :system do
  self.use_transactional_tests = false

  before(:each) do
    truncate_db
  end

  after(:each) do
    truncate_db
  end

  it "redirects an empty-DB visit to the root path through to /setup instead of /admin/sign_in" do
    expect(User.count).to eq(0)

    visit "/"

    expect(page).to have_current_path("/setup", ignore_query: true)
    expect(page).to have_text(/admin account|create your/i)
  end

  it "creates the user, signs them in, seeds categories and merchant rules, and lands them on the analytics dashboard" do
    expect(User.count).to eq(0)

    visit "/setup"
    fill_in "user[name]",                  with: "First Run Owner"
    fill_in "user[email]",                 with: "first-run-#{SecureRandom.hex(4)}@example.test"
    fill_in "user[password]",              with: "Password123!"
    fill_in "user[password_confirmation]", with: "Password123!"
    click_button "Create account & sign in"

    expect(page).to have_current_path("/admin/analytics", ignore_query: true)
    expect(User.count).to eq(1)
    user = User.first
    expect(user.categories.count).to be > 0
    expect(user.merchant_rules.count).to be > 0
  end

  it "redirects /setup to /admin/sign_in once a user already exists and the visitor is signed out" do
    User.create!(email: "owner-#{SecureRandom.hex(4)}@example.test", password: "Password123!", name: "Existing")

    visit "/setup"

    expect(page).to have_current_path(new_user_session_path, ignore_query: true)
  end

  it "is idempotent on the server side: POST /setup is a no-op once a user exists, even if the form was open in another tab" do
    User.create!(email: "owner-#{SecureRandom.hex(4)}@example.test", password: "Password123!", name: "Existing")

    page.driver.post("/setup", {
      user: {
        name: "Race Loser",
        email: "race-loser@example.test",
        password: "Password123!",
        password_confirmation: "Password123!"
      },
      authenticity_token: "skip"
    })

    expect(User.where(email: "race-loser@example.test")).to be_empty
    expect(User.count).to eq(1)
  end

  it "rejects setup with mismatched password confirmation by re-rendering :new and not creating a user" do
    expect(User.count).to eq(0)

    visit "/setup"
    fill_in "user[name]",                  with: "Mismatch"
    fill_in "user[email]",                 with: "mismatch-#{SecureRandom.hex(4)}@example.test"
    fill_in "user[password]",              with: "Password123!"
    fill_in "user[password_confirmation]", with: "WrongPass456!"
    click_button "Create account & sign in"

    expect(User.count).to eq(0)
    expect(page).to have_current_path("/setup", ignore_query: true)
    expect(page).to have_text(/confirmation/i)
  end

  it "rejects setup with a blank email by re-rendering :new with a presence error" do
    expect(User.count).to eq(0)

    visit "/setup"
    fill_in "user[name]",                  with: "No Email"
    fill_in "user[email]",                 with: ""
    fill_in "user[password]",              with: "Password123!"
    fill_in "user[password_confirmation]", with: "Password123!"
    click_button "Create account & sign in"

    expect(User.count).to eq(0)
    expect(page).to have_current_path("/setup", ignore_query: true)
    expect(page).to have_text(/email/i)
  end

  it "still routes to /setup when an unauthenticated visitor deep-links to /admin/analytics on a fresh DB" do
    expect(User.count).to eq(0)

    visit "/admin/analytics"

    expect(page).to have_current_path("/setup", ignore_query: true)
  end
end
