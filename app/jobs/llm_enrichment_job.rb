# frozen_string_literal: true

# Drives an llm_enrichment OperationRun. Follows the same pattern as
# TransactionSyncJob: thin wrapper around the domain service, owns the
# OperationRun lifecycle and live-progress broadcasting.
#
# Summary structure stored in operation_runs.summary (JSONB):
#   {
#     "total_groups" => N,
#     "auto_applied" => N,
#     "pending_review" => N,
#     "skipped" => N,
#     "batches" => [
#       { "index" => 0, "size" => 15, "status" => "succeeded",
#         "auto" => 3, "pending" => 2, "skipped" => 0, "errors" => [] },
#       { "index" => 1, "size" => 5,  "status" => "failed",
#         "auto" => 0, "pending" => 0, "skipped" => 0,
#         "errors" => [{ "title" => "...", "error" => "..." }] }
#     ]
#   }
class LlmEnrichmentJob < ApplicationJob
  queue_as :default

  KIND = "llm_enrichment"

  def perform(operation_run_id)
    run = OperationRun.find(operation_run_id)
    return if run.terminal?

    run.start!
    summary = { "total_groups" => 0, "auto_applied" => 0, "pending_review" => 0, "skipped" => 0, "batches" => [] }

    on_batch = ->(index:, size:, status:, auto:, pending:, skipped:, errors:, request: nil, response: nil) {
      summary["batches"] << {
        "index"    => index,
        "size"     => size,
        "status"   => status,
        "auto"     => auto,
        "pending"  => pending,
        "skipped"  => skipped,
        "errors"   => errors.map { |e| { "title" => e[:title], "error" => e[:error] } },
        "request"  => request,
        "response" => response
      }
      run.update!(summary: summary)
    }

    limit  = run.params["limit"]&.to_i || Llm::EnrichmentRunner::DEFAULT_LIMIT
    # The run subject is always the user (set by LlmEnrichmentsController#create).
    # Defensive fallback to triggered_by_user lets us re-run older runs that
    # may have been queued before per-user scoping landed.
    user   = run.subject.is_a?(User) ? run.subject : run.triggered_by_user
    raise "OperationRun #{run.id} has no resolvable user — cannot enrich" if user.nil?

    result = Llm::EnrichmentRunner.call(user: user, limit: limit, on_batch: on_batch)

    summary["total_groups"]   = result.processed
    summary["auto_applied"]   = result.auto_applied
    summary["pending_review"] = result.pending_review
    summary["skipped"]        = result.skipped

    if result.errors.any? && result.auto_applied.zero? && result.pending_review.zero?
      run.fail!(error: "All batches failed. First: #{result.errors.first[:error]}", summary: summary)
    elsif result.errors.any?
      run.mark_partial!(summary: summary, error: "#{result.errors.size} item(s) failed.")
    else
      run.succeed!(summary: summary)
    end
  rescue StandardError => e
    run&.fail!(error: "#{e.class.name}: #{e.message}", summary: summary)
    raise
  end
end
