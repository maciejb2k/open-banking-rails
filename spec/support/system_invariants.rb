# frozen_string_literal: true

# Cross-cutting invariants asserted at the end of system specs and selected
# domain specs. Each invariant is one method so a regression flips a single
# helper, not 30 specs. The catalog mirrors section 09 of the testing map.
module SystemInvariants
  def assert_no_running_operation_runs!
    stuck = OperationRun.running.pluck(:id, :kind, :started_at)
    raise "Operation runs stuck in :running — #{stuck.inspect}" if stuck.any?
  end

  def assert_ledger_sums_match!(user)
    bank_sum   = BankTransaction.for_user(user).sum(:amount_cents)
    manual_sum = ManualTransaction.for_user(user).sum(:amount_cents)
    ledger_sum = LedgerEntry.for_user(user).sum(:amount_cents)
    expected   = bank_sum + manual_sum
    return if ledger_sum == expected

    raise "LedgerEntry sum #{ledger_sum} does not equal source-table sum #{expected} for user #{user.id}"
  end

  def assert_user_isolation!(user_a, user_b)
    a_ids = BankTransaction.for_user(user_a).pluck(:id)
    b_ids = BankTransaction.for_user(user_b).pluck(:id)
    overlap = a_ids & b_ids
    raise "Cross-user leak: shared BankTransaction ids #{overlap.inspect}" if overlap.any?
  end

  def assert_no_orphaned_enrichments!(user)
    orphans = TransactionEnrichment.for_user(user).where(enrichable_id: nil).pluck(:id)
    raise "Orphaned enrichments: #{orphans.inspect}" if orphans.any?
  end
end

RSpec.configure do |config|
  config.include SystemInvariants
end
