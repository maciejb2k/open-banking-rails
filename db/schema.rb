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

ActiveRecord::Schema[8.1].define(version: 2026_04_29_190000) do
  # These are extensions that must be enabled in order to support this database
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
    t.string "name"
    t.string "product"
    t.jsonb "raw_account_resource"
    t.text "raw_balances"
    t.jsonb "raw_details"
    t.string "status", default: "active", null: false
    t.bigint "tpp_credential_id", null: false
    t.datetime "transactions_synced_at"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.string "usage"
    t.index ["current_bank_connection_id"], name: "index_bank_accounts_on_current_bank_connection_id"
    t.index ["iban"], name: "index_bank_accounts_on_iban"
    t.index ["status"], name: "index_bank_accounts_on_status"
    t.index ["tpp_credential_id"], name: "index_bank_accounts_on_tpp_credential_id"
    t.index ["uid"], name: "index_bank_accounts_on_uid", unique: true
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
    t.index ["payment_method"], name: "index_bank_transactions_on_payment_method"
    t.index ["status"], name: "index_bank_transactions_on_status"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "archived_at"
    t.string "color"
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "kind", default: "expense", null: false
    t.string "name", null: false
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["archived_at"], name: "index_categories_on_archived_at"
    t.index ["parent_id", "position"], name: "index_categories_on_parent_id_and_position"
    t.index ["parent_id"], name: "index_categories_on_parent_id"
    t.index ["slug"], name: "index_categories_on_slug", unique: true
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
    t.index ["approved_by_id"], name: "index_merchant_rules_on_approved_by_id"
    t.index ["enabled", "priority"], name: "index_merchant_rules_on_enabled_and_priority"
    t.index ["field", "pattern"], name: "index_merchant_rules_on_field_and_pattern"
    t.index ["merchant_id"], name: "index_merchant_rules_on_merchant_id"
    t.index ["source"], name: "index_merchant_rules_on_source"
  end

  create_table "merchants", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "archived_at"
    t.decimal "confidence", precision: 4, scale: 3
    t.datetime "created_at", null: false
    t.bigint "default_category_id"
    t.string "display_name"
    t.string "kind"
    t.string "logo_url"
    t.string "model"
    t.string "name", null: false
    t.text "notes"
    t.string "slug", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_merchants_on_approved_by_id"
    t.index ["archived_at"], name: "index_merchants_on_archived_at"
    t.index ["default_category_id"], name: "index_merchants_on_default_category_id"
    t.index ["name"], name: "index_merchants_on_name"
    t.index ["slug"], name: "index_merchants_on_slug", unique: true
    t.index ["source"], name: "index_merchants_on_source"
  end

  create_table "operation_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "finished_at"
    t.string "kind", null: false
    t.jsonb "params", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.jsonb "summary", default: {}, null: false
    t.string "trigger", default: "manual", null: false
    t.bigint "triggered_by_user_id"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_operation_runs_on_created_at"
    t.index ["kind", "status"], name: "index_operation_runs_on_kind_and_status"
    t.index ["kind"], name: "index_operation_runs_on_kind"
    t.index ["status"], name: "index_operation_runs_on_status"
    t.index ["subject_type", "subject_id"], name: "index_operation_runs_on_subject"
    t.index ["triggered_by_user_id"], name: "index_operation_runs_on_triggered_by_user_id"
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
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_transaction_enrichments_on_category_id"
    t.index ["enrichable_type", "enrichable_id"], name: "idx_enrichments_on_enrichable", unique: true
    t.index ["enrichable_type", "enrichable_id"], name: "index_transaction_enrichments_on_enrichable"
    t.index ["merchant_id"], name: "index_transaction_enrichments_on_merchant_id"
    t.index ["merchant_rule_id"], name: "index_transaction_enrichments_on_merchant_rule_id"
    t.index ["source"], name: "index_transaction_enrichments_on_source"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
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
  add_foreign_key "bank_connections", "bank_connections", column: "replaces_id"
  add_foreign_key "bank_connections", "tpp_credentials"
  add_foreign_key "bank_transactions", "bank_accounts"
  add_foreign_key "categories", "categories", column: "parent_id"
  add_foreign_key "merchant_rules", "merchants"
  add_foreign_key "merchant_rules", "users", column: "approved_by_id"
  add_foreign_key "merchants", "categories", column: "default_category_id"
  add_foreign_key "merchants", "users", column: "approved_by_id"
  add_foreign_key "operation_runs", "users", column: "triggered_by_user_id"
  add_foreign_key "tpp_credentials", "users"
  add_foreign_key "transaction_enrichments", "categories"
  add_foreign_key "transaction_enrichments", "merchant_rules"
  add_foreign_key "transaction_enrichments", "merchants"
end
