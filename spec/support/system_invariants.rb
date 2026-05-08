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
    signed_sql = "CASE direction WHEN 'credit' THEN amount_cents ELSE -amount_cents END"
    bank_signed   = BankTransaction.for_user(user).sum(signed_sql)
    manual_signed = ManualTransaction.for_user(user).sum(signed_sql)
    bank_unsigned   = BankTransaction.for_user(user).sum(:amount_cents)
    manual_unsigned = ManualTransaction.for_user(user).sum(:amount_cents)
    bank_count   = BankTransaction.for_user(user).count
    manual_count = ManualTransaction.for_user(user).count

    ledger_signed   = LedgerEntry.for_user(user).sum(:signed_amount_cents)
    ledger_unsigned = LedgerEntry.for_user(user).sum(:amount_cents)
    ledger_count    = LedgerEntry.for_user(user).count

    if ledger_signed != bank_signed + manual_signed
      raise "LedgerEntry signed sum #{ledger_signed} != source signed sum #{bank_signed + manual_signed} for user #{user.id}"
    end

    if ledger_unsigned != bank_unsigned + manual_unsigned
      raise "LedgerEntry unsigned sum #{ledger_unsigned} != source unsigned sum #{bank_unsigned + manual_unsigned} for user #{user.id}"
    end

    if ledger_count != bank_count + manual_count
      raise "LedgerEntry row count #{ledger_count} != source row count #{bank_count + manual_count} for user #{user.id}"
    end
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
