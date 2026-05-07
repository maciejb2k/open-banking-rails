# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Meta area", type: :request do
  it "GET /admin/styleguide redirects an anonymous request to sign-in" do
    create(:user)
    get admin_styleguide_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "GET /admin/styleguide renders 200 for a signed-in user, exercising every reusable component partial" do
    user = create(:user)
    sign_in user

    get admin_styleguide_path

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/versions returns 200 even when no version rows exist" do
    user = create(:user)
    sign_in user

    get admin_versions_path

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/versions/:id returns 200 for a recorded version when PaperTrail is enabled", :papertrail do
    user = create(:user)
    sign_in user
    version = nil
    PaperTrail.request(whodunnit: user.id.to_s) do
      credential = create(:tpp_credential, user: user, name: "First")
      credential.update!(name: "Renamed")
      version = credential.versions.last
    end
    expect(version).to be_present

    get admin_version_path(version.id)

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/versions/:id returns 404 for an unknown id" do
    user = create(:user)
    sign_in user

    get admin_version_path(999_999_999)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/versions without sign-in redirects to /admin/sign_in" do
    create(:user)
    get admin_versions_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
