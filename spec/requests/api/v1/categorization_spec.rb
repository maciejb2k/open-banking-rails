# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v1 categorization resources", type: :request do
  it "GET /api/v1/categories lists the user's active categories" do
    user = create(:user)
    other = create(:user)
    own = create(:category, user: user, name: "OWN-CAT")
    create(:category, user: other, name: "FOREIGN-CAT")
    raw, _ = issue_pat(user)

    api_get("/api/v1/categories", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    names = body.map { |row| row["name"] }
    expect(names).to include(own.name)
    expect(names).not_to include("FOREIGN-CAT")
  end

  it "GET /api/v1/categories?include_archived=true includes archived rows" do
    user = create(:user)
    create(:category, :archived, user: user, name: "ARCHIVED-CAT")
    raw, _ = issue_pat(user)

    api_get("/api/v1/categories", token: raw, params: { include_archived: "true" })

    body = JSON.parse(response.body)
    names = body.map { |row| row["name"] }
    expect(names).to include("ARCHIVED-CAT")
  end

  it "POST /api/v1/categories creates a category via Categories::Creator and 201s" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_post("/api/v1/categories", token: raw, params: {
      name: "Coffee", kind: "expense", color: "amber", icon: "coffee"
    })

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["name"]).to eq("Coffee")
    expect(user.categories.find_by(name: "Coffee")).to be_present
  end

  it "POST /api/v1/categories returns 422 when the name is blank" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_post("/api/v1/categories", token: raw, params: { kind: "expense" })

    expect(response).to have_http_status(:bad_request).or have_http_status(:unprocessable_content)
  end

  it "GET /api/v1/categories/:id returns 404 for another user's category" do
    user = create(:user)
    other = create(:user)
    foreign = create(:category, user: other)
    raw, _ = issue_pat(user)

    api_get("/api/v1/categories/#{foreign.id}", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "PATCH /api/v1/categories/:id moves the category via Categories::Mover" do
    user = create(:user)
    cat = create(:category, user: user, name: "Old")
    raw, _ = issue_pat(user)

    api_patch("/api/v1/categories/#{cat.id}", token: raw, params: { name: "New" })

    expect(response).to have_http_status(:ok)
    expect(cat.reload.name).to eq("New")
  end

  it "DELETE /api/v1/categories/:id refuses to delete an in-use category" do
    user = create(:user)
    cat = create(:category, user: user)
    allow_any_instance_of(Category).to receive(:in_use?).and_return(true)
    raw, _ = issue_pat(user)

    expect {
      api_delete("/api/v1/categories/#{cat.id}", token: raw)
    }.not_to change(Category, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "DELETE /api/v1/categories/:id deletes an unused category and 204s" do
    user = create(:user)
    cat = create(:category, user: user)
    allow_any_instance_of(Category).to receive(:in_use?).and_return(false)
    raw, _ = issue_pat(user)

    api_delete("/api/v1/categories/#{cat.id}", token: raw)

    expect(response).to have_http_status(:no_content)
  end

  it "POST /api/v1/categories/:id/archive marks the category as archived" do
    user = create(:user)
    cat = create(:category, user: user)
    raw, _ = issue_pat(user)

    api_post("/api/v1/categories/#{cat.id}/archive", token: raw)

    expect(response).to have_http_status(:ok).or have_http_status(:created)
    expect(cat.reload.archived_at).to be_present
  end

  it "GET /api/v1/merchants lists only the current user's merchants" do
    user = create(:user)
    other = create(:user)
    own = create(:merchant, user: user, name: "OWN-API-MERCH")
    create(:merchant, user: other, name: "FOREIGN-API-MERCH")
    raw, _ = issue_pat(user)

    api_get("/api/v1/merchants", token: raw)

    body = JSON.parse(response.body)
    names = body["data"].map { |row| row["name"] }
    expect(names).to include(own.name)
    expect(names).not_to include("FOREIGN-API-MERCH")
  end

  it "GET /api/v1/merchants?source=user filters by source" do
    user = create(:user)
    user_merch = create(:merchant, user: user, source: "user", name: "USER-MERCH-API")
    llm_merch = create(:merchant, :llm, user: user, name: "LLM-MERCH-API")
    raw, _ = issue_pat(user)

    api_get("/api/v1/merchants", token: raw, params: { source: "user" })

    body = JSON.parse(response.body)
    names = body["data"].map { |r| r["name"] }
    expect(names).to include(user_merch.name)
    expect(names).not_to include(llm_merch.name)
  end

  it "POST /api/v1/merchants creates a merchant via Merchants::Creator and 201s" do
    user = create(:user)
    raw, _ = issue_pat(user)

    api_post("/api/v1/merchants", token: raw, params: { name: "Biedronka API", kind: "company" })

    expect(response).to have_http_status(:created)
    expect(user.merchants.find_by(name: "Biedronka API")).to be_present
  end

  it "GET /api/v1/merchants/:id returns 404 for another user's merchant" do
    user = create(:user)
    other = create(:user)
    foreign = create(:merchant, user: other)
    raw, _ = issue_pat(user)

    api_get("/api/v1/merchants/#{foreign.id}", token: raw)

    expect(response).to have_http_status(:not_found)
  end

  it "PATCH /api/v1/merchants/:id updates the merchant" do
    user = create(:user)
    merch = create(:merchant, user: user, name: "Old")
    raw, _ = issue_pat(user)

    api_patch("/api/v1/merchants/#{merch.id}", token: raw, params: { name: "New" })

    expect(response).to have_http_status(:ok)
    expect(merch.reload.name).to eq("New")
  end

  it "DELETE /api/v1/merchants/:id refuses when transactions still reference the merchant" do
    user = create(:user)
    merch = create(:merchant, user: user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, bank_account: bank_account)
    create(:transaction_enrichment, enrichable: bank_tx, merchant: merch)
    raw, _ = issue_pat(user)

    api_delete("/api/v1/merchants/#{merch.id}", token: raw)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "POST /api/v1/merchants/:id/approve delegates to Merchants::Approver" do
    user = create(:user)
    merch = create(:merchant, :llm, user: user)
    success = Merchants::Approver::Result.new(success?: true, merchant: merch)
    allow(Merchants::Approver).to receive(:call).and_return(success)
    raw, _ = issue_pat(user)

    api_post("/api/v1/merchants/#{merch.id}/approve", token: raw)

    expect(Merchants::Approver).to have_received(:call).with(merchant: merch, actor: user)
  end

  it "GET /api/v1/merchants/:m_id/rules lists rules for the merchant" do
    user = create(:user)
    merch = create(:merchant, user: user)
    rule = create(:merchant_rule, owner: user, merchant: merch, pattern: "API-RULE-PATTERN")
    raw, _ = issue_pat(user)

    api_get("/api/v1/merchants/#{merch.id}/rules", token: raw)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.map { |row| row["id"] }).to include(rule.id)
  end

  it "POST /api/v1/merchants/:m_id/rules creates a rule via MerchantRules::Creator and 201s" do
    user = create(:user)
    merch = create(:merchant, user: user)
    rule = build_stubbed(:merchant_rule, owner: user, merchant: merch)
    success = MerchantRules::Creator::Result.new(success?: true, rule: rule)
    allow(MerchantRules::Creator).to receive(:call).and_return(success)
    raw, _ = issue_pat(user)

    api_post("/api/v1/merchants/#{merch.id}/rules", token: raw, params: {
      kind: "contains", field: "title", pattern: "BIEDRONKA"
    })

    expect(MerchantRules::Creator).to have_received(:call).with(merchant: merch, actor: user, attributes: hash_including("pattern" => "BIEDRONKA"))
    expect(response).to have_http_status(:created)
  end

  it "PATCH /api/v1/merchants/:m_id/rules/:id delegates to MerchantRules::Updater" do
    user = create(:user)
    merch = create(:merchant, user: user)
    rule = create(:merchant_rule, owner: user, merchant: merch)
    success = MerchantRules::Updater::Result.new(success?: true, rule: rule)
    allow(MerchantRules::Updater).to receive(:call).and_return(success)
    raw, _ = issue_pat(user)

    api_patch("/api/v1/merchants/#{merch.id}/rules/#{rule.id}", token: raw, params: { pattern: "NEW" })

    expect(MerchantRules::Updater).to have_received(:call).with(rule: rule, actor: user, attributes: hash_including("pattern" => "NEW"))
  end

  it "DELETE /api/v1/merchants/:m_id/rules/:id delegates to MerchantRules::Destroyer and 204s" do
    user = create(:user)
    merch = create(:merchant, user: user)
    rule = create(:merchant_rule, owner: user, merchant: merch)
    allow(MerchantRules::Destroyer).to receive(:call).and_return(MerchantRules::Destroyer::Result.new(success?: true))
    raw, _ = issue_pat(user)

    api_delete("/api/v1/merchants/#{merch.id}/rules/#{rule.id}", token: raw)

    expect(MerchantRules::Destroyer).to have_received(:call).with(rule: rule, actor: user)
    expect(response).to have_http_status(:no_content)
  end

  it "GET /api/v1/llm_enrichments lists only runs triggered by the current user" do
    user = create(:user)
    other = create(:user)
    own_run = create(:operation_run, kind: "llm_enrichment", triggered_by_user: user, subject: user)
    foreign_run = create(:operation_run, kind: "llm_enrichment", triggered_by_user: other, subject: other)
    raw, _ = issue_pat(user)

    api_get("/api/v1/llm_enrichments", token: raw)

    body = JSON.parse(response.body)
    ids = body["data"].map { |row| row["id"] }
    expect(ids).to include(own_run.id)
    expect(ids).not_to include(foreign_run.id)
  end

  it "POST /api/v1/llm_enrichments returns 422 when the LLM is not configured" do
    user = create(:user)
    raw, _ = issue_pat(user)
    failure = LlmEnrichments::Queuer::Result.new(success?: false, error_messages: [ "LLM not configured" ])
    allow(LlmEnrichments::Queuer).to receive(:call).and_return(failure)

    api_post("/api/v1/llm_enrichments", token: raw, params: {})

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["message"]).to match(/not configured/i)
  end

  it "POST /api/v1/llm_enrichments delegates to Queuer on success and 201s" do
    user = create(:user)
    run = create(:operation_run, kind: "llm_enrichment", triggered_by_user: user, subject: user)
    allow(LlmEnrichments::Queuer).to receive(:call).and_return(
      LlmEnrichments::Queuer::Result.new(success?: true, run: run)
    )
    raw, _ = issue_pat(user)

    api_post("/api/v1/llm_enrichments", token: raw, params: { limit: 5 })

    expect(LlmEnrichments::Queuer).to have_received(:call) do |kwargs|
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:input].limit).to eq(5)
    end
    expect(response).to have_http_status(:created)
  end
end
