# frozen_string_literal: true

class UpdateLedgerEntriesToV02 < ActiveRecord::Migration[8.1]
  def change
    update_view :ledger_entries, version: 2, revert_to_version: 1
  end
end
