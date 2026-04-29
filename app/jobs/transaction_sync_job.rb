# frozen_string_literal: true

# Drives a transaction_sync OperationRun. Thin wrapper around the
# domain operations (EnableBanking::Operations::Sync*Transactions) —
# adds OperationRun lifecycle (start/succeed/partial/fail) and live
# progress via the on_account_synced callback.
#
# The actual work lives in the operations; the job owns scheduling
# and the run-tracking record. Synchronous callers (rake, console)
# can use the operations directly without ever touching this job.
#
# Future cron (2x/day): a tiny scheduler creates an
# OperationRun(trigger: "scheduled", subject: user) per active user
# and enqueues this job.
class TransactionSyncJob < ApplicationJob
  queue_as :default

  KIND = "transaction_sync"

  def perform(operation_run_id)
    run = OperationRun.find(operation_run_id)
    return if run.terminal? # idempotent guard

    run.start!
    summary = { accounts: [] }

    on_progress = ->(account:, outcome:) {
      summary[:accounts] << account_entry(account, outcome)
      run.update!(summary: summary)
    }

    invoke_operation(run, on_progress)

    OperationRunFinalizer.call(run, summary)

    # Enrichment runs after sync finalization — idempotent and only touches
    # rows without an existing enrichment, so it's safe even on partial
    # failures (failed accounts contribute no new transactions).
    enrich_new_transactions(run)
  rescue StandardError => e
    run&.fail!(error: "#{e.class.name}: #{e.message}", summary: summary)
    raise
  end

  private

  # Scopes the enricher to whichever account(s) this run touched, so a
  # per-account run doesn't scan the whole table. Failures here are logged
  # but don't fail the run — sync already succeeded; enrichment can be
  # retried separately.
  def enrich_new_transactions(run)
    scope = scoped_pending_transactions(run)
    return if scope.nil?
    Enrichment::TransactionEnricher.enrich_pending(scope)
  rescue StandardError => e
    Rails.logger.error("[TransactionSyncJob] Enrichment failed for run=#{run.id}: #{e.class}: #{e.message}")
  end

  def scoped_pending_transactions(run)
    base = BankTransaction.without_enrichment
    case run.subject
    when BankAccount    then base.where(bank_account_id: run.subject.id)
    when BankConnection then base.where(bank_account_id: run.subject.current_bank_accounts.select(:id))
    when User           then base.for_user(run.subject)
    end
  end

  # Dispatch to the right domain operation based on what the run is scoped to.
  def invoke_operation(run, on_progress)
    common = {
      date_from: run.params["date_from"],
      date_to: run.params["date_to"],
      on_account_synced: on_progress
    }

    case run.subject
    when User
      EnableBanking::Operations::SyncUserTransactions.call(run.subject, **common)
    when BankConnection
      EnableBanking::Operations::SyncConnectionTransactions.call(run.subject, **common)
    when BankAccount
      outcome = begin
        EnableBanking::Operations::SyncAccountTransactions.call(run.subject, date_from: common[:date_from], date_to: common[:date_to])
      rescue EnableBanking::Operations::SyncAccountTransactions::Failed => e
        e
      end
      on_progress.call(account: run.subject, outcome: outcome)
    else
      run.fail!(error: "Unsupported subject: #{run.subject_type}##{run.subject_id}")
    end
  end

  # Per-account row appended to summary[:accounts]. outcome is either an
  # Outcome struct (success) or a Failed exception (per-account error).
  def account_entry(account, outcome)
    base = {
      bank_account_id: account.id,
      iban: account.iban,
      bank: account.current_bank_connection&.bank_name
    }

    if outcome.respond_to?(:inserted)
      base.merge(
        status: "succeeded",
        inserted: outcome.inserted,
        skipped: outcome.skipped,
        pages_fetched: outcome.pages_fetched,
        truncated: outcome.truncated,
        date_from: outcome.date_from.to_s,
        date_to: outcome.date_to.to_s
      )
    else
      base.merge(
        status: "failed",
        error: outcome.is_a?(Exception) ? outcome.message : outcome.to_s
      )
    end
  end
end
