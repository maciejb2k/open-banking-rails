# frozen_string_literal: true

# Derived metadata for any ledger entry (BankTransaction today, ManualTransaction
# tomorrow). Polymorphic from day 1 to avoid a future schema migration.
#
# This table is rebuildable: `DROP TABLE transaction_enrichments` and a re-run
# of TransactionEnricher restores everything from raw data + rules - except
# rows where the user made an explicit decision (source: 'manual' or
# category_overridden: true), which are preserved across rebuilds.
#
# `category_id` is an explicit override. When NULL, the effective category is
# derived at read time from `merchant.default_category` - keeps merchant
# default changes flowing to existing transactions automatically.
class CreateTransactionEnrichments < ActiveRecord::Migration[8.1]
  def change
    create_table :transaction_enrichments do |t|
      t.references :enrichable, polymorphic: true, null: false
      t.references :merchant, foreign_key: true
      t.references :category, foreign_key: true
      t.boolean :category_overridden, null: false, default: false
      t.string  :source, null: false                # unmatched|system_rule|user_rule|llm_rule|llm_pending|manual
      t.references :merchant_rule, foreign_key: true
      t.decimal :confidence, precision: 4, scale: 3
      t.string  :model
      t.text    :notes
      t.datetime :enriched_at

      t.timestamps
    end

    add_index :transaction_enrichments, [ :enrichable_type, :enrichable_id ],
              unique: true, name: "idx_enrichments_on_enrichable"
    add_index :transaction_enrichments, :source
  end
end
