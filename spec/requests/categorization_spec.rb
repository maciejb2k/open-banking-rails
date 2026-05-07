# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categorization area", type: :request do
  it "GET /admin/categories returns 200 listing only the current user's categories" do
    user = create(:user)
    other = create(:user)
    own = create(:category, user: user, name: "MY-FOOD-CAT")
    foreign = create(:category, user: other, name: "FOREIGN-CAT-XYZ")
    sign_in user

    get admin_categories_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own.name)
    expect(response.body).not_to include(foreign.name)
  end

  it "GET /admin/categories/new returns 200 carrying the parent_path query param" do
    user = create(:user)
    sign_in user

    get new_admin_category_path, params: { parent_path: "food.groceries" }

    expect(response).to have_http_status(:ok)
  end

  it "POST /admin/categories delegates to Categories::Creator on success" do
    user = create(:user)
    saved = create(:category, user: user, name: "Saved Category")
    success = Categories::Creator::Result.new(success?: true, category: saved)
    allow(Categories::Creator).to receive(:call).and_return(success)
    sign_in user

    post admin_categories_path, params: {
      category: { name: "Saved Category", kind: "expense", color: "emerald", icon: "tag", essential: false, position: 0, parent_path: nil }
    }

    expect(Categories::Creator).to have_received(:call) do |kwargs|
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:attributes][:name]).to eq("Saved Category")
    end
    expect(response).to redirect_to(admin_categories_path)
  end

  it "POST /admin/categories re-renders :new with 422 when the creator fails" do
    user = create(:user)
    half_built = Category.new(user: user, name: "")
    failure = Categories::Creator::Result.new(success?: false, category: half_built, error_messages: [ "name can't be blank" ])
    allow(Categories::Creator).to receive(:call).and_return(failure)
    sign_in user

    post admin_categories_path, params: {
      category: { name: "", kind: "expense", color: "emerald", icon: "tag", essential: false, position: 0 }
    }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "GET /admin/categories/:id/edit returns 200 for the user's own category" do
    user = create(:user)
    cat = create(:category, user: user)
    sign_in user

    get edit_admin_category_path(cat)

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/categories/:id/edit returns 404 for another user's category" do
    user = create(:user)
    other = create(:user)
    foreign = create(:category, user: other)
    sign_in user

    get edit_admin_category_path(foreign)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/categories/:id/edit redirects when the category is hidden" do
    user = create(:user)
    cat = create(:category, user: user)
    UserHiddenCategory.create!(user: user, category: cat)
    sign_in user

    get edit_admin_category_path(cat)

    expect(response).to redirect_to(admin_categories_path)
    expect(flash[:alert]).to match(/private/i)
  end

  it "PATCH /admin/categories/:id delegates to Categories::Mover on success" do
    user = create(:user)
    cat = create(:category, user: user)
    success = Categories::Mover::Result.new(success?: true, category: cat)
    allow(Categories::Mover).to receive(:call).and_return(success)
    sign_in user

    patch admin_category_path(cat), params: {
      category: { name: cat.name, kind: cat.kind, color: cat.color, icon: cat.icon, essential: cat.essential, position: cat.position, parent_path: nil }
    }

    expect(Categories::Mover).to have_received(:call) do |kwargs|
      expect(kwargs[:category]).to eq(cat)
    end
    expect(response).to redirect_to(admin_categories_path)
  end

  it "PATCH /admin/categories/:id re-renders :edit with 422 on failure" do
    user = create(:user)
    cat = create(:category, user: user)
    failure = Categories::Mover::Result.new(success?: false, category: cat, error_messages: [ "bad" ])
    allow(Categories::Mover).to receive(:call).and_return(failure)
    sign_in user

    patch admin_category_path(cat), params: {
      category: { name: "x", kind: "expense", color: "emerald", icon: "tag", essential: false, position: 0 }
    }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "DELETE /admin/categories/:id refuses an in-use category and keeps the row" do
    user = create(:user)
    cat = create(:category, user: user)
    allow_any_instance_of(Category).to receive(:in_use?).and_return(true)
    sign_in user

    expect {
      delete admin_category_path(cat)
    }.not_to change(Category, :count)
    expect(response).to redirect_to(admin_categories_path)
    expect(flash[:alert]).to match(/in use|sub-categories/i)
  end

  it "DELETE /admin/categories/:id deletes an unused category" do
    user = create(:user)
    cat = create(:category, user: user)
    allow_any_instance_of(Category).to receive(:in_use?).and_return(false)
    sign_in user

    expect {
      delete admin_category_path(cat)
    }.to change { user.categories.count }.by(-1)
    expect(response).to redirect_to(admin_categories_path)
  end

  it "POST /admin/categories/:id/archive flips the archived_at timestamp" do
    user = create(:user)
    cat = create(:category, user: user)
    sign_in user

    expect {
      post archive_admin_category_path(cat)
    }.to change { cat.reload.archived_at }.from(nil)
    expect(response).to redirect_to(admin_categories_path)
  end

  it "POST /admin/categories/:id/unarchive clears the archived_at timestamp" do
    user = create(:user)
    cat = create(:category, :archived, user: user)
    sign_in user

    post unarchive_admin_category_path(cat)

    expect(cat.reload.archived_at).to be_nil
    expect(response).to redirect_to(admin_categories_path)
  end

  it "GET /admin/merchants returns 200 listing only the current user's merchants" do
    user = create(:user)
    other = create(:user)
    own = create(:merchant, user: user, name: "OWN-MERCH-7777")
    foreign = create(:merchant, user: other, name: "FOREIGN-MERCH-8888")
    sign_in user

    get admin_merchants_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own.name)
    expect(response.body).not_to include(foreign.name)
  end

  it "GET /admin/merchants filters by source" do
    user = create(:user)
    user_merch = create(:merchant, user: user, source: "user", name: "USER-MERCH-AAAA")
    llm_merch = create(:merchant, :llm, user: user, name: "LLM-MERCH-ZZZZ")
    sign_in user

    get admin_merchants_path, params: { source: "user" }

    expect(response.body).to include(user_merch.name)
    expect(response.body).not_to include(llm_merch.name)
  end

  it "GET /admin/merchants filters by free-text q on name" do
    user = create(:user)
    matching = create(:merchant, user: user, name: "Biedronka Polska")
    nonmatching = create(:merchant, user: user, name: "Other Store")
    sign_in user

    get admin_merchants_path, params: { q: "Biedronka" }

    expect(response.body).to include(matching.name)
    expect(response.body).not_to include(nonmatching.name)
  end

  it "GET /admin/merchants/:id returns 200 happy path" do
    user = create(:user)
    merch = create(:merchant, user: user)
    sign_in user

    get admin_merchant_path(merch)

    expect(response).to have_http_status(:ok)
  end

  it "GET /admin/merchants/:id returns 404 for another user's merchant" do
    user = create(:user)
    other = create(:user)
    foreign = create(:merchant, user: other)
    sign_in user

    get admin_merchant_path(foreign)

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/merchants/:id redirects when the default category is hidden" do
    user = create(:user)
    cat = create(:category, user: user)
    merch = create(:merchant, user: user, default_category: cat)
    UserHiddenCategory.create!(user: user, category: cat)
    sign_in user

    get admin_merchant_path(merch)

    expect(response).to redirect_to(admin_merchants_path)
    expect(flash[:alert]).to match(/hidden/i)
  end

  it "POST /admin/merchants delegates to Merchants::Creator on success" do
    user = create(:user)
    saved = create(:merchant, user: user, name: "New Merch")
    success = Merchants::Creator::Result.new(success?: true, merchant: saved)
    allow(Merchants::Creator).to receive(:call).and_return(success)
    sign_in user

    post admin_merchants_path, params: {
      merchant: { name: "New Merch", slug: "new_merch", kind: "company", default_category_id: nil, logo_url: nil, notes: nil }
    }

    expect(Merchants::Creator).to have_received(:call).with(user: user, attributes: hash_including(name: "New Merch"))
    expect(response).to redirect_to(admin_merchant_path(saved))
  end

  it "POST /admin/merchants re-renders :new with 422 when the creator fails" do
    user = create(:user)
    half_built = Merchant.new(user: user, name: "")
    failure = Merchants::Creator::Result.new(success?: false, merchant: half_built, error_messages: [ "name can't be blank" ])
    allow(Merchants::Creator).to receive(:call).and_return(failure)
    sign_in user

    post admin_merchants_path, params: {
      merchant: { name: "", slug: "", kind: "company", default_category_id: nil, logo_url: nil, notes: nil }
    }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "PATCH /admin/merchants/:id with a safe return_to redirects to that path on success" do
    user = create(:user)
    merch = create(:merchant, user: user)
    sign_in user

    patch admin_merchant_path(merch), params: {
      merchant: { name: "Updated Name", slug: merch.slug, kind: merch.kind, default_category_id: nil, logo_url: nil, notes: nil },
      return_to: "/admin/categories"
    }

    expect(response).to redirect_to("/admin/categories")
  end

  it "PATCH /admin/merchants/:id with a hostile return_to falls back to the merchant show path" do
    user = create(:user)
    merch = create(:merchant, user: user)
    sign_in user

    patch admin_merchant_path(merch), params: {
      merchant: { name: "Updated Name", slug: merch.slug, kind: merch.kind, default_category_id: nil, logo_url: nil, notes: nil },
      return_to: "https://evil.example/admin/something"
    }

    expect(response).to redirect_to(admin_merchant_path(merch))
  end

  it "DELETE /admin/merchants/:id refuses when transactions still reference the merchant" do
    user = create(:user)
    merch = create(:merchant, user: user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, bank_account: bank_account)
    create(:transaction_enrichment, enrichable: bank_tx, merchant: merch)
    sign_in user

    expect {
      delete admin_merchant_path(merch)
    }.not_to change(Merchant, :count)
    expect(response).to redirect_to(admin_merchant_path(merch))
    expect(flash[:alert]).to match(/linked|archive/i)
  end

  it "DELETE /admin/merchants/:id deletes an unreferenced merchant" do
    user = create(:user)
    merch = create(:merchant, user: user)
    sign_in user

    expect {
      delete admin_merchant_path(merch)
    }.to change(Merchant, :count).by(-1)
  end

  it "POST /admin/merchants/:id/archive flips archived_at" do
    user = create(:user)
    merch = create(:merchant, user: user)
    sign_in user

    expect {
      post archive_admin_merchant_path(merch)
    }.to change { merch.reload.archived_at }.from(nil)
  end

  it "POST /admin/merchants/:id/approve delegates to Merchants::Approver" do
    user = create(:user)
    merch = create(:merchant, :llm, user: user)
    success = Merchants::Approver::Result.new(success?: true, merchant: merch)
    allow(Merchants::Approver).to receive(:call).and_return(success)
    sign_in user

    post approve_admin_merchant_path(merch)

    expect(Merchants::Approver).to have_received(:call).with(merchant: merch, actor: user)
    expect(response).to redirect_to(admin_merchant_path(merch))
    expect(flash[:notice]).to match(/approved/i)
  end

  it "POST /admin/merchants/:m_id/merchant_rules delegates to MerchantRules::Creator on success" do
    user = create(:user)
    merch = create(:merchant, user: user)
    rule = create(:merchant_rule, owner: user, merchant: merch)
    allow(MerchantRules::Creator).to receive(:call)
      .and_return(MerchantRules::Creator::Result.new(success?: true, rule: rule))
    sign_in user

    post admin_merchant_merchant_rules_path(merch), params: {
      merchant_rule: { kind: "contains", field: "title", pattern: "BIEDRONKA", case_sensitive: false, priority: 0, enabled: true }
    }

    expect(MerchantRules::Creator).to have_received(:call).with(merchant: merch, actor: user, attributes: hash_including(pattern: "BIEDRONKA"))
    expect(response).to redirect_to(admin_merchant_path(merch))
    expect(flash[:notice]).to be_present
  end

  it "POST /admin/merchants/:m_id/merchant_rules redirects with alert when the creator fails" do
    user = create(:user)
    merch = create(:merchant, user: user)
    failure = MerchantRules::Creator::Result.new(success?: false, error_messages: [ "pattern can't be blank" ])
    allow(MerchantRules::Creator).to receive(:call).and_return(failure)
    sign_in user

    post admin_merchant_merchant_rules_path(merch), params: {
      merchant_rule: { kind: "contains", field: "title", pattern: "", case_sensitive: false, priority: 0, enabled: true }
    }

    expect(response).to redirect_to(admin_merchant_path(merch))
    expect(flash[:alert]).to match(/pattern/i)
  end

  it "PATCH /admin/merchants/:m_id/merchant_rules/:id delegates to MerchantRules::Updater" do
    user = create(:user)
    merch = create(:merchant, user: user)
    rule = create(:merchant_rule, owner: user, merchant: merch)
    allow(MerchantRules::Updater).to receive(:call)
      .and_return(MerchantRules::Updater::Result.new(success?: true, rule: rule))
    sign_in user

    patch admin_merchant_merchant_rule_path(merch, rule), params: {
      merchant_rule: { kind: "contains", field: "title", pattern: "ZABKA", case_sensitive: false, priority: 5, enabled: true }
    }

    expect(MerchantRules::Updater).to have_received(:call).with(rule: rule, actor: user, attributes: hash_including(pattern: "ZABKA"))
    expect(response).to redirect_to(admin_merchant_path(merch))
  end

  it "DELETE /admin/merchants/:m_id/merchant_rules/:id delegates to MerchantRules::Destroyer" do
    user = create(:user)
    merch = create(:merchant, user: user)
    rule = create(:merchant_rule, owner: user, merchant: merch)
    allow(MerchantRules::Destroyer).to receive(:call)
      .and_return(MerchantRules::Destroyer::Result.new(success?: true))
    sign_in user

    delete admin_merchant_merchant_rule_path(merch, rule)

    expect(MerchantRules::Destroyer).to have_received(:call).with(rule: rule, actor: user)
    expect(response).to redirect_to(admin_merchant_path(merch))
  end

  it "PATCH /admin/bank_transactions/:bt_id/enrichment delegates to ClassificationApplier on success" do
    user = create(:user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, bank_account: bank_account)
    success = Enrichment::ClassificationApplier::Result.new(success: true, message: "Enrichment updated.")
    allow(Enrichment::ClassificationApplier).to receive(:call).and_return(success)
    sign_in user

    patch admin_bank_transaction_enrichment_path(bank_tx), params: {
      enrichment: { mode: "only_this", merchant_id: nil, category_id: nil }
    }

    expect(Enrichment::ClassificationApplier).to have_received(:call) do |kwargs|
      expect(kwargs[:transaction]).to eq(bank_tx)
      expect(kwargs[:actor]).to eq(user)
      expect(kwargs[:input]).to be_a(Enrichment::ClassificationApplier::Input)
      expect(kwargs[:input].mode).to eq("only_this")
    end
    expect(response).to redirect_to(admin_bank_transaction_path(bank_tx))
    expect(flash[:notice]).to eq("Enrichment updated.")
  end

  it "PATCH /admin/bank_transactions/:bt_id/enrichment passes nil merchant for a foreign merchant_id" do
    user = create(:user)
    other = create(:user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, bank_account: bank_account)
    foreign_merch = create(:merchant, user: other)
    allow(Enrichment::ClassificationApplier).to receive(:call)
      .and_return(Enrichment::ClassificationApplier::Result.new(success: true, message: "ok"))
    sign_in user

    patch admin_bank_transaction_enrichment_path(bank_tx), params: {
      enrichment: { mode: "set_merchant", merchant_id: foreign_merch.id }
    }

    expect(Enrichment::ClassificationApplier).to have_received(:call) do |kwargs|
      expect(kwargs[:input].merchant).to be_nil
    end
  end

  it "PATCH /admin/bank_transactions/:bt_id/enrichment routes a failure to flash[:alert]" do
    user = create(:user)
    bank_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: user))
    bank_tx = create(:bank_transaction, bank_account: bank_account)
    failure = Enrichment::ClassificationApplier::Result.new(success: false, message: "Bad mode")
    allow(Enrichment::ClassificationApplier).to receive(:call).and_return(failure)
    sign_in user

    patch admin_bank_transaction_enrichment_path(bank_tx), params: {
      enrichment: { mode: "junk" }
    }

    expect(response).to redirect_to(admin_bank_transaction_path(bank_tx))
    expect(flash[:alert]).to eq("Bad mode")
  end

  it "PATCH /admin/bank_transactions/:bt_id/enrichment returns 404 for another user's transaction" do
    user = create(:user)
    other = create(:user)
    foreign_account = create(:bank_account, tpp_credential: create(:tpp_credential, user: other))
    foreign_tx = create(:bank_transaction, bank_account: foreign_account)
    sign_in user

    patch admin_bank_transaction_enrichment_path(foreign_tx), params: { enrichment: { mode: "only_this" } }

    expect(response).to have_http_status(:not_found)
  end

  it "GET /admin/llm_enrichments lists only the current user's runs" do
    user = create(:user)
    other = create(:user)
    create(:category, user: user)
    own_run = create(:operation_run, kind: "llm_enrichment", triggered_by_user: user, subject: user)
    foreign_run = create(:operation_run, kind: "llm_enrichment", triggered_by_user: other, subject: other)
    sign_in user

    get admin_llm_enrichments_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_llm_enrichment_path(own_run))
    expect(response.body).not_to include(admin_llm_enrichment_path(foreign_run))
  end

  it "POST /admin/llm_enrichments redirects to LLM preferences with alert when the LLM isn't configured" do
    user = create(:user)
    sign_in user
    failure = LlmEnrichments::Queuer::Result.new(success?: false, error_messages: [ "LLM not configured" ])
    allow(LlmEnrichments::Queuer).to receive(:call).and_return(failure)

    post admin_llm_enrichments_path

    expect(response).to redirect_to(admin_settings_preferences_llm_path)
    expect(flash[:alert]).to match(/not configured/i)
  end

  it "POST /admin/llm_enrichments delegates to Queuer on success and redirects to the run page" do
    user = create(:user)
    run = create(:operation_run, kind: "llm_enrichment", triggered_by_user: user, subject: user)
    success = LlmEnrichments::Queuer::Result.new(success?: true, run: run)
    allow(LlmEnrichments::Queuer).to receive(:call).and_return(success)
    sign_in user

    post admin_llm_enrichments_path, params: { limit: "5" }

    expect(LlmEnrichments::Queuer).to have_received(:call) do |kwargs|
      expect(kwargs[:user]).to eq(user)
      expect(kwargs[:input].limit).to eq("5")
    end
    expect(response).to redirect_to(admin_llm_enrichment_path(run))
  end

  it "GET /admin/matching_engine returns 200 listing only the current user's rules" do
    user = create(:user)
    other = create(:user)
    create(:category, user: user)
    own_rule = create(:merchant_rule, owner: user, pattern: "MY-PATTERN-XYZ")
    foreign_rule = create(:merchant_rule, owner: other, pattern: "FOREIGN-PATTERN-789")
    sign_in user

    get admin_matching_engine_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_rule.pattern)
    expect(response.body).not_to include(foreign_rule.pattern)
  end

  it "GET /admin/categories without sign-in redirects to /admin/sign_in" do
    create(:user)
    get admin_categories_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
