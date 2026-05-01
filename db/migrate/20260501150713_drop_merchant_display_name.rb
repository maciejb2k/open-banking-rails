# frozen_string_literal: true

# `display_name` was a redundant duplicate of `name` — every code path
# (seeders, LLM enricher, own-account merchant syncer) set both to the
# same value, and `Merchant#display` fell back to `name` when
# display_name was blank. No call site ever benefited from the split.
#
# After: a single `name` column. `Merchant#display` stays as an alias so
# 12+ view templates keep working without churn.
class DropMerchantDisplayName < ActiveRecord::Migration[8.1]
  def change
    remove_column :merchants, :display_name, :string
  end
end
