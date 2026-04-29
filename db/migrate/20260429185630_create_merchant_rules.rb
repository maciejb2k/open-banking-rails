# frozen_string_literal: true

# Pattern-matching rules that map raw transaction fields → Merchant.
#
# A rule fires when `pattern` matches the chosen `field` according to `kind`:
#   contains | regex | exact | prefix | iban
#
# Resolution order in TransactionEnricher: enabled rules sorted by
# (priority DESC, source rank: user > llm > system, id ASC). First match wins.
# That ordering guarantees user corrections always beat LLM proposals which
# always beat seeded system rules.
#
# LLM-generated rules carry `confidence` and `model`. Below the auto-apply
# threshold they're created with `enabled: false` and surfaced in a review
# queue; on approval the user flips `enabled` and sets approved_by/at.
class CreateMerchantRules < ActiveRecord::Migration[8.1]
  def change
    create_table :merchant_rules do |t|
      t.references :merchant, null: false, foreign_key: true
      t.string  :kind, null: false                  # contains|regex|exact|prefix|iban
      t.string  :field, null: false                 # title|counterparty_name|counterparty_iban
      t.string  :pattern, null: false
      t.boolean :case_sensitive, null: false, default: false
      t.integer :priority, null: false, default: 0
      t.string  :source, null: false                # system|user|llm
      t.decimal :confidence, precision: 4, scale: 3
      t.string  :model
      t.boolean :enabled, null: false, default: true
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at

      t.timestamps
    end

    add_index :merchant_rules, [ :enabled, :priority ]
    add_index :merchant_rules, [ :field, :pattern ]
    add_index :merchant_rules, :source
  end
end
