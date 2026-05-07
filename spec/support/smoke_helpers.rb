# frozen_string_literal: true

# Helpers for the auto-generating smoke crawler in
# spec/system/smoke/admin_spec.rb. The crawler enumerates every admin GET
# route, substitutes ids from the seeded showcase, and asserts that each
# page renders with a 200 and standard chrome.
module SmokeHelpers
  SKIP_PATTERNS = [
    %r{/sidekiq},
    %r{/admin/debug},
    %r{/rails/}
  ].freeze

  def enumerate_admin_get_routes(showcase: nil)
    routes = Rails.application.routes.routes.select do |route|
      verbs = Array(route.verb.is_a?(String) ? route.verb.split("|") : route.verb)
      next false unless verbs.include?("GET")
      path = route.path.spec.to_s.sub("(.:format)", "")
      next false unless path.start_with?("/admin")
      next false if SKIP_PATTERNS.any? { |re| path =~ re }
      true
    end

    routes.map do |route|
      path = route.path.spec.to_s.sub("(.:format)", "")
      [ path, route.name ]
    end
  end

  def assert_renders_ok(path)
    visit path
    expect(page.status_code).to eq(200), "expected 200 for #{path}, got #{page.status_code}"
    expect(page).to have_css("body")
  end

  def assert_admin_chrome_present
    expect(page).to have_css("nav, header, [role='navigation']")
  end
end

RSpec.configure do |config|
  config.include SmokeHelpers, type: :system
end
