# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_02_170613) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "ltree"
  enable_extension "pg_catalog.plpgsql"

  create_table "bank_accounts", force: :cascade do |t|
    t.jsonb "account_servicer"
    t.jsonb "all_account_ids", default: [], null: false
    t.datetime "balances_synced_at"
    t.string "bban"
    t.string "cash_account_type"
    t.datetime "created_at", null: false
    t.string "currency"
    t.bigint "current_bank_connection_id"
    t.string "details"
    t.datetime "details_fetched_at"
    t.string "iban"
    t.boolean "manual", default: false, null: false
    t.bigint "manual_owner_id"
    t.string "name"
    t.string "product"
    t.jsonb "raw_account_resource"
    t.text "raw_balances"
    t.jsonb "raw_details"
    t.string "status", default: "active", null: false
    t.bigint "tpp_credential_id"
    t.datetime "transactions_synced_at"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.string "usage"
    t.index ["current_bank_connection_id"], name: "index_bank_accounts_on_current_bank_connection_id"
    t.index ["iban"], name: "index_bank_accounts_on_iban"
    t.index ["manual"], name: "index_bank_accounts_on_manual"
    t.index ["manual_owner_id"], name: "index_bank_accounts_on_manual_owner_id"
    t.index ["status"], name: "index_bank_accounts_on_status"
    t.index ["tpp_credential_id"], name: "index_bank_accounts_on_tpp_credential_id"
    t.index ["uid"], name: "index_bank_accounts_on_uid", unique: true
    t.check_constraint "manual = true AND tpp_credential_id IS NULL AND manual_owner_id IS NOT NULL OR manual = false AND tpp_credential_id IS NOT NULL AND manual_owner_id IS NULL", name: "bank_accounts_ownership_xor"
  end

  create_table "bank_connections", force: :cascade do |t|
    t.boolean "access_balances", default: true, null: false
    t.boolean "access_transactions", default: true, null: false
    t.datetime "authorized_at"
    t.string "bank_country", default: "PL"
    t.string "bank_name"
    t.string "bank_slug", null: false
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.text "last_error"
    t.datetime "last_refreshed_at"
    t.datetime "last_synced_at"
    t.text "psu_id_hash"
    t.string "psu_type", default: "personal"
    t.text "raw_session_payload"
    t.bigint "replaces_id"
    t.text "session_id"
    t.string "status", default: "pending", null: false
    t.bigint "tpp_credential_id", null: false
    t.datetime "updated_at", null: false
    t.datetime "valid_until"
    t.index ["replaces_id"], name: "index_bank_connections_on_replaces_id"
    t.index ["status"], name: "index_bank_connections_on_status"
    t.index ["tpp_credential_id", "bank_slug", "status"], name: "index_bank_connections_lookup"
    t.index ["tpp_credential_id"], name: "index_bank_connections_on_tpp_credential_id"
    t.index ["valid_until"], name: "index_bank_connections_on_valid_until"
  end

  create_table "bank_transactions", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.bigint "bank_account_id", null: false
    t.string "bank_transaction_code"
    t.date "booking_date", null: false
    t.string "counterparty_iban"
    t.string "counterparty_kind", default: "unknown", null: false
    t.string "counterparty_name"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.string "direction", null: false
    t.string "external_id", null: false
    t.datetime "fetched_at", null: false
    t.string "payment_method"
    t.text "raw_payload", null: false
    t.string "status", default: "booked", null: false
    t.text "title"
    t.date "transaction_date"
    t.string "type_hint"
    t.datetime "updated_at", null: false
    t.date "value_date"
    t.index ["bank_account_id", "booking_date"], name: "index_bank_transactions_on_bank_account_id_and_booking_date"
    t.index ["bank_account_id", "external_id"], name: "index_bank_transactions_on_bank_account_id_and_external_id", unique: true
    t.index ["bank_account_id"], name: "index_bank_transactions_on_bank_account_id"
    t.index ["counterparty_kind"], name: "index_bank_transactions_on_counterparty_kind"
    t.index ["payment_method"], name: "index_bank_transactions_on_payment_method"
    t.index ["status"], name: "index_bank_transactions_on_status"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "archived_at"
    t.string "color"
    t.datetime "created_at", null: false
    t.boolean "essential", default: false, null: false
    t.string "icon"
    t.string "kind", default: "expense", null: false
    t.string "name", null: false
    t.ltree "path"
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["archived_at"], name: "index_categories_on_archived_at"
    t.index ["path"], name: "index_categories_on_path", using: :gist
    t.index ["path"], name: "index_categories_on_path_unique", unique: true
    t.index ["user_id", "slug"], name: "index_categories_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "gutentag_taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tag_id", null: false
    t.bigint "taggable_id", null: false
    t.string "taggable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_gutentag_taggings_on_tag_id"
    t.index ["taggable_type", "taggable_id", "tag_id"], name: "unique_taggings", unique: true
    t.index ["taggable_type", "taggable_id"], name: "index_gutentag_taggings_on_taggable_type_and_taggable_id"
  end

  create_table "gutentag_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "taggings_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_gutentag_tags_on_name", unique: true
    t.index ["taggings_count"], name: "index_gutentag_tags_on_taggings_count"
  end

  create_table "llm_settings", force: :cascade do |t|
    t.text "api_key", null: false
    t.datetime "created_at", null: false
    t.text "last_test_error"
    t.datetime "last_tested_at"
    t.string "model"
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_llm_settings_on_user_id", unique: true
  end

  create_table "manual_transactions", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.bigint "bank_account_id", null: false
    t.date "booking_date", null: false
    t.string "counterparty_kind", default: "unknown", null: false
    t.string "counterparty_name"
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id", null: false
    t.string "currency", limit: 3, null: false
    t.string "direction", null: false
    t.bigint "linked_bank_transaction_id"
    t.text "note"
    t.string "payment_method"
    t.string "source", default: "manual", null: false
    t.string "status", default: "booked", null: false
    t.text "title"
    t.date "transaction_date"
    t.datetime "updated_at", null: false
    t.index ["bank_account_id", "booking_date"], name: "index_manual_transactions_on_bank_account_id_and_booking_date"
    t.index ["bank_account_id"], name: "index_manual_transactions_on_bank_account_id"
    t.index ["counterparty_kind"], name: "index_manual_transactions_on_counterparty_kind"
    t.index ["created_by_user_id"], name: "index_manual_transactions_on_created_by_user_id"
    t.index ["linked_bank_transaction_id"], name: "idx_manual_transactions_one_per_linked_bank_tx", unique: true, where: "(linked_bank_transaction_id IS NOT NULL)"
    t.index ["linked_bank_transaction_id"], name: "index_manual_transactions_on_linked_bank_transaction_id"
    t.index ["payment_method"], name: "index_manual_transactions_on_payment_method"
    t.index ["status"], name: "index_manual_transactions_on_status"
  end

  create_table "merchant_rules", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.boolean "case_sensitive", default: false, null: false
    t.decimal "confidence", precision: 4, scale: 3
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "field", null: false
    t.string "kind", null: false
    t.bigint "merchant_id", null: false
    t.string "model"
    t.string "pattern", null: false
    t.integer "priority", default: 0, null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["approved_by_id"], name: "index_merchant_rules_on_approved_by_id"
    t.index ["enabled", "priority"], name: "index_merchant_rules_on_enabled_and_priority"
    t.index ["field", "pattern"], name: "index_merchant_rules_on_field_and_pattern"
    t.index ["merchant_id"], name: "index_merchant_rules_on_merchant_id"
    t.index ["source"], name: "index_merchant_rules_on_source"
    t.index ["user_id"], name: "index_merchant_rules_on_user_id"
  end

  create_table "merchants", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "archived_at"
    t.decimal "confidence", precision: 4, scale: 3
    t.datetime "created_at", null: false
    t.bigint "default_category_id"
    t.string "kind"
    t.string "logo_url"
    t.string "model"
    t.string "name", null: false
    t.text "notes"
    t.string "slug", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["approved_by_id"], name: "index_merchants_on_approved_by_id"
    t.index ["archived_at"], name: "index_merchants_on_archived_at"
    t.index ["default_category_id"], name: "index_merchants_on_default_category_id"
    t.index ["name"], name: "index_merchants_on_name"
    t.index ["source"], name: "index_merchants_on_source"
    t.index ["user_id", "slug"], name: "index_merchants_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_merchants_on_user_id"
  end

  create_table "operation_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "finished_at"
    t.string "kind", null: false
    t.jsonb "params", default: {}, null: false
    t.datetime "scheduled_for"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.jsonb "summary", default: {}, null: false
    t.string "trigger", default: "manual", null: false
    t.bigint "triggered_by_user_id", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_operation_runs_on_created_at"
    t.index ["kind", "status"], name: "index_operation_runs_on_kind_and_status"
    t.index ["kind"], name: "index_operation_runs_on_kind"
    t.index ["status"], name: "index_operation_runs_on_status"
    t.index ["subject_type", "subject_id", "kind", "scheduled_for"], name: "index_operation_runs_scheduled_for_idempotency", unique: true, where: "(scheduled_for IS NOT NULL)"
    t.index ["subject_type", "subject_id"], name: "index_operation_runs_on_subject"
    t.index ["triggered_by_user_id"], name: "index_operation_runs_on_triggered_by_user_id"
  end

  create_table "sync_schedules", force: :cascade do |t|
    t.bigint "bank_connection_id", null: false
    t.string "cadence", default: "daily", null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "last_dispatched_at"
    t.datetime "next_run_at"
    t.datetime "paused_until"
    t.integer "preferred_hour", default: 8, null: false
    t.datetime "updated_at", null: false
    t.index ["bank_connection_id"], name: "index_sync_schedules_on_bank_connection_id", unique: true
    t.index ["enabled", "next_run_at"], name: "index_sync_schedules_due", where: "(enabled = true)"
  end

  create_table "tpp_credentials", force: :cascade do |t|
    t.text "application_id"
    t.datetime "cert_expires_at"
    t.datetime "created_at", null: false
    t.string "environment"
    t.text "last_verification_error"
    t.datetime "last_verified_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.boolean "primary", default: false, null: false
    t.text "private_key_pem"
    t.string "provider", default: "enable_banking", null: false
    t.text "public_cert_pem"
    t.string "redirect_url"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider"], name: "index_tpp_credentials_on_provider"
    t.index ["status"], name: "index_tpp_credentials_on_status"
    t.index ["user_id"], name: "index_one_primary_tpp_credential_per_user", unique: true, where: "(\"primary\" = true)"
    t.index ["user_id"], name: "index_tpp_credentials_on_user_id"
  end

  create_table "transaction_enrichments", force: :cascade do |t|
    t.bigint "category_id"
    t.boolean "category_overridden", default: false, null: false
    t.decimal "confidence", precision: 4, scale: 3
    t.datetime "created_at", null: false
    t.bigint "enrichable_id", null: false
    t.string "enrichable_type", null: false
    t.datetime "enriched_at"
    t.bigint "merchant_id"
    t.bigint "merchant_rule_id"
    t.string "model"
    t.text "notes"
    t.string "recurrence_interval"
    t.boolean "recurring", default: false, null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_transaction_enrichments_on_category_id"
    t.index ["enrichable_type", "enrichable_id"], name: "idx_enrichments_on_enrichable", unique: true
    t.index ["enrichable_type", "enrichable_id"], name: "index_transaction_enrichments_on_enrichable"
    t.index ["merchant_id"], name: "index_transaction_enrichments_on_merchant_id"
    t.index ["merchant_rule_id"], name: "index_transaction_enrichments_on_merchant_rule_id"
    t.index ["recurring"], name: "index_transaction_enrichments_on_recurring", where: "(recurring = true)"
    t.index ["source"], name: "index_transaction_enrichments_on_source"
  end

  create_table "user_hidden_categories", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["category_id"], name: "index_user_hidden_categories_on_category_id"
    t.index ["user_id", "category_id"], name: "index_user_hidden_categories_on_user_id_and_category_id", unique: true
    t.index ["user_id"], name: "index_user_hidden_categories_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.boolean "track_cash", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.text "object_changes"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "bank_accounts", "bank_connections", column: "current_bank_connection_id"
  add_foreign_key "bank_accounts", "tpp_credentials"
  add_foreign_key "bank_accounts", "users", column: "manual_owner_id"
  add_foreign_key "bank_connections", "bank_connections", column: "replaces_id"
  add_foreign_key "bank_connections", "tpp_credentials"
  add_foreign_key "bank_transactions", "bank_accounts"
  add_foreign_key "categories", "users"
  add_foreign_key "llm_settings", "users"
  add_foreign_key "manual_transactions", "bank_accounts"
  add_foreign_key "manual_transactions", "bank_transactions", column: "linked_bank_transaction_id"
  add_foreign_key "manual_transactions", "users", column: "created_by_user_id"
  add_foreign_key "merchant_rules", "merchants"
  add_foreign_key "merchant_rules", "users"
  add_foreign_key "merchant_rules", "users", column: "approved_by_id"
  add_foreign_key "merchants", "categories", column: "default_category_id"
  add_foreign_key "merchants", "users"
  add_foreign_key "merchants", "users", column: "approved_by_id"
  add_foreign_key "operation_runs", "users", column: "triggered_by_user_id"
  add_foreign_key "sync_schedules", "bank_connections"
  add_foreign_key "tpp_credentials", "users"
  add_foreign_key "transaction_enrichments", "categories"
  add_foreign_key "transaction_enrichments", "merchant_rules"
  add_foreign_key "transaction_enrichments", "merchants"
  add_foreign_key "user_hidden_categories", "categories"
  add_foreign_key "user_hidden_categories", "users"

  create_view "ledger_entries", sql_definition: <<-SQL
      SELECT 'BankTransaction'::text AS source_type,
      bt.id AS source_id,
      bt.bank_account_id,
      bt.amount_cents,
      bt.currency,
      bt.direction,
          CASE bt.direction
              WHEN 'credit'::text THEN bt.amount_cents
              ELSE (- bt.amount_cents)
          END AS signed_amount_cents,
      bt.status,
      bt.booking_date,
      bt.transaction_date,
      bt.payment_method,
      bt.title,
      bt.counterparty_name,
      bt.counterparty_kind,
      te.id AS enrichment_id,
      te.merchant_id,
      COALESCE(te.category_id, m.default_category_id) AS effective_category_id,
      c.path AS category_path,
      COALESCE(c.essential, false) AS essential,
      COALESCE(te.recurring, false) AS recurring,
      te.recurrence_interval,
      te.source AS enrichment_source
     FROM (((bank_transactions bt
       LEFT JOIN transaction_enrichments te ON ((((te.enrichable_type)::text = 'BankTransaction'::text) AND (te.enrichable_id = bt.id))))
       LEFT JOIN merchants m ON ((m.id = te.merchant_id)))
       LEFT JOIN categories c ON ((c.id = COALESCE(te.category_id, m.default_category_id))))
  UNION ALL
   SELECT 'ManualTransaction'::text AS source_type,
      mt.id AS source_id,
      mt.bank_account_id,
      mt.amount_cents,
      mt.currency,
      mt.direction,
          CASE mt.direction
              WHEN 'credit'::text THEN mt.amount_cents
              ELSE (- mt.amount_cents)
          END AS signed_amount_cents,
      mt.status,
      mt.booking_date,
      mt.transaction_date,
      mt.payment_method,
      mt.title,
      mt.counterparty_name,
      mt.counterparty_kind,
      te.id AS enrichment_id,
      te.merchant_id,
      COALESCE(te.category_id, m.default_category_id) AS effective_category_id,
      c.path AS category_path,
      COALESCE(c.essential, false) AS essential,
      COALESCE(te.recurring, false) AS recurring,
      te.recurrence_interval,
      te.source AS enrichment_source
     FROM (((manual_transactions mt
       LEFT JOIN transaction_enrichments te ON ((((te.enrichable_type)::text = 'ManualTransaction'::text) AND (te.enrichable_id = mt.id))))
       LEFT JOIN merchants m ON ((m.id = te.merchant_id)))
       LEFT JOIN categories c ON ((c.id = COALESCE(te.category_id, m.default_category_id))));
  SQL
end
