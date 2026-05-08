# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin smoke crawler", :smoke, type: :system do
  self.use_transactional_tests = false

  before(:all) do
    truncate_db
    @showcase_user, @showcase_fake_eb, @showcase_fake_llm = setup_showcase
  end

  after(:all) do
    truncate_db
  end

  before(:each) do
    allow(EnableBanking::Client).to receive(:new) { @showcase_fake_eb }
    allow(Llm::Client).to receive(:for) { @showcase_fake_llm }
    sign_in_as(@showcase_user)
  end

  let(:user) { @showcase_user }

  let(:substitutions) do
    {
      "id" => {
        "bank_connections"     => -> { user.bank_connections.first&.id },
        "bank_accounts"        => -> { user.owned_bank_accounts.first&.id },
        "bank_transactions"    => -> { BankTransaction.for_user(user).first&.id },
        "cash_transactions"    => -> { ManualTransaction.for_user(user).first&.id },
        "categories"           => -> { user.categories.first&.id },
        "merchants"            => -> { user.merchants.first&.id },
        "tpp_credentials"      => -> { user.tpp_credentials.first&.id },
        "transaction_syncs"    => -> { OperationRun.where(triggered_by_user: user, kind: "transaction_sync").first&.id },
        "llm_enrichments"      => -> { OperationRun.where(triggered_by_user: user, kind: "llm_enrichment").first&.id },
        "versions"             => -> { PaperTrail::Version.first&.id }
      },
      "slug" => {
        "categories" => -> { user.categories.where.not(slug: nil).first&.slug },
        "merchants"  => -> { user.merchants.first&.slug }
      },
      "bank_connection_id" => -> { user.bank_connections.first&.id },
      "bank_transaction_id" => -> { BankTransaction.for_user(user).first&.id },
      "merchant_id" => -> { user.merchants.first&.id }
    }
  end

  skip_paths = [
    "/admin/sign_in",
    "/admin/password/new",
    "/admin/password/edit",
    "/admin/versions",
    "/admin/versions/:id",
    "/admin/llm_enrichments/:id"
  ].freeze

  enumerated = Rails.application.routes.routes.filter_map do |route|
    verbs = Array(route.verb.is_a?(String) ? route.verb.split("|") : route.verb)
    next nil unless verbs.include?("GET")
    path = route.path.spec.to_s.sub("(.:format)", "")
    next nil unless path.start_with?("/admin")
    next nil if path.include?("/sidekiq") || path.include?("/debug")
    next nil if skip_paths.include?(path)
    [ path, route.name ]
  end.uniq

  enumerated.each do |path, name|
    it "renders #{path} (#{name})" do
      resolved = resolve_path(path, substitutions)
      skip "no fixture id available for #{path} in the showcase" if resolved.nil?

      visit resolved

      expect([ 200, 301, 302 ]).to include(page.status_code), "GET #{resolved} returned #{page.status_code}"
    end
  end

  def resolve_path(path, substitutions)
    out = path.dup

    out = out.gsub(%r{/admin/(?<resource>[a-z_]+)/:id/edit\z}) do
      resource = Regexp.last_match[:resource]
      id = substitutions["id"][resource]&.call
      return nil if id.nil?
      "/admin/#{resource}/#{id}/edit"
    end

    out = out.gsub(%r{/admin/(?<resource>[a-z_]+)/:id\z}) do
      resource = Regexp.last_match[:resource]
      id = substitutions["id"][resource]&.call
      return nil if id.nil?
      "/admin/#{resource}/#{id}"
    end

    out = out.gsub(%r{/admin/analytics/(?<resource>categories|merchants)/:slug\z}) do
      resource = Regexp.last_match[:resource]
      slug = substitutions["slug"][resource]&.call
      return nil if slug.nil?
      "/admin/analytics/#{resource}/#{slug}"
    end

    out = out.gsub(":bank_connection_id")  { substitutions["bank_connection_id"].call.to_s }
    out = out.gsub(":bank_transaction_id") { substitutions["bank_transaction_id"].call.to_s }
    out = out.gsub(":merchant_id")         { substitutions["merchant_id"].call.to_s }
    out
  end
end
