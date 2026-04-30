# frozen_string_literal: true

module Admin
  # LLM enrichment runs — follows the same pattern as TransactionSyncsController.
  #
  #   GET  /admin/llm_enrichments       — dashboard: stats, review queue, run history, trigger form
  #   POST /admin/llm_enrichments       — create OperationRun, enqueue job, redirect to show
  #   GET  /admin/llm_enrichments/:id   — live progress via Turbo Streams
  class LlmEnrichmentsController < BaseController
    KIND = "llm_enrichment"

    def index
      user_enrichments = TransactionEnrichment.for_user(current_user)
      @merchantless_count = user_enrichments.merchantless.count
      @suggestible_count  = merchantless_with_signal.count
      @group_count        = build_group_count
      @new_groups_count   = Llm::EnrichmentRunner.new(user: current_user).send(:build_groups, merchantless_with_signal).size
      @api_key_set        = ENV["OPENAI_API_KEY"].present? || ENV["GEMINI_API_KEY"].present?

      @pending_merchants = current_user.merchants.where(source: "llm", approved_at: nil)
                                       .includes(:default_category, :merchant_rules)
                                       .order(created_at: :desc)

      scope = OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id)
      @pagy, @runs = paginated(scope, default_sort: "created_at desc")
    end

    def show
      @run = scoped_runs.find(params[:id])
    end

    def create
      unless ENV["OPENAI_API_KEY"].present? || ENV["GEMINI_API_KEY"].present?
        redirect_to admin_llm_enrichments_path, alert: "OPENAI_API_KEY missing in ENV."
        return
      end

      run = OperationRun.create!(
        kind:              KIND,
        status:            "queued",
        trigger:           "manual",
        triggered_by_user: current_user,
        subject:           current_user,
        params:            { "limit" => (params[:limit].presence&.to_i || Llm::EnrichmentRunner::DEFAULT_LIMIT) },
        summary:           {}
      )

      LlmEnrichmentJob.perform_later(run.id)
      redirect_to admin_llm_enrichment_path(run), notice: "Run ##{run.id} queued."
    end

    private

    def scoped_runs
      OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id)
    end

    # Defer to the runner so the dashboard always shows what an actual run
    # would process. Avoids drifting filters between display and execution.
    def merchantless_with_signal
      Llm::EnrichmentRunner.new(user: current_user).send(:default_scope)
    end

    def build_group_count
      keys = merchantless_with_signal.pluck(:title, :counterparty_name).map do |t, cp|
        [ Enrichment::TitleNormalizer.call(t), cp.to_s ]
      end
      keys.uniq.count { |k| k != [ "", "" ] }
    end
  end
end
