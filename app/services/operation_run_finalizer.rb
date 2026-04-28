# frozen_string_literal: true

# Decides the terminal status of an OperationRun based on the per-account
# outcomes accumulated in `summary[:accounts]`. Mapping:
#
#   no accounts touched → failed   ("No accounts in scope")
#   all succeeded       → succeeded
#   mixed               → partial  ("N account(s) failed")
#   all failed          → failed   ("All N account(s) failed")
#
# Pulled out of TransactionSyncJob so the same rule can be reused by future
# kinds (balance_refresh, account_details_refresh) and tested without
# spinning up a Sidekiq job.
class OperationRunFinalizer
  def self.call(run, summary)
    new(run, summary).call
  end

  def initialize(run, summary)
    @run = run
    @summary = summary
  end

  def call
    case
    when account_statuses.empty?           then @run.fail!(error: "No accounts in scope", summary: @summary)
    when all_succeeded?                    then @run.succeed!(summary: @summary)
    when any_succeeded?                    then @run.mark_partial!(summary: @summary, error: partial_message)
    else                                        @run.fail!(error: total_failure_message, summary: @summary)
    end
  end

  private

  def account_statuses
    @account_statuses ||= Array(@summary[:accounts]).map { |a| a[:status] }
  end

  def all_succeeded?
    account_statuses.all? { |s| s == "succeeded" }
  end

  def any_succeeded?
    account_statuses.any? { |s| s == "succeeded" }
  end

  def partial_message
    "#{account_statuses.count('failed')} account(s) failed"
  end

  def total_failure_message
    "All #{account_statuses.size} account(s) failed"
  end
end
