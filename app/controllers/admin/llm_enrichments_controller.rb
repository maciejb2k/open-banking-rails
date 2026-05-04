# frozen_string_literal: true

module Admin
  class LlmEnrichmentsController < BaseController
    KIND = "llm_enrichment"

    def index
      user_enrichments = TransactionEnrichment.for_user(current_user)
      enrichable_scope = Llm::EnrichableQuery.scope(user: current_user)

      @merchantless_count = user_enrichments.merchantless.count
      @suggestible_count  = enrichable_scope.count
      @group_count        = build_group_count(enrichable_scope)
      # Same scope as @group_count, but excludes groups already covered by an
      # existing MerchantRule - those won't be sent to the LLM on the next run.
      @new_groups_count   = Llm::EnrichableQuery.groups(user: current_user, scope: enrichable_scope).size
      @llm_setting        = current_user.llm_setting
      @api_key_set        = @llm_setting&.configured?

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
      result = LlmEnrichments::Queuer.call(
        user:  current_user,
        input: LlmEnrichments::Queuer::Input.new(limit: params[:limit])
      )
      if result.success?
        redirect_to admin_llm_enrichment_path(result.run), notice: "Run ##{result.run.id} queued."
      else
        redirect_to admin_settings_preferences_llm_path, alert: result.error
      end
    end

    private

    def scoped_runs
      OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id)
    end

    # Every group costs ~1 LLM call - drives the cost preview. Counts ALL
    # groups, including ones already covered by a MerchantRule; pair with
    # @new_groups_count for the delta.
    def build_group_count(scope)
      keys = scope.pluck(:title, :counterparty_name).map do |t, cp|
        [ Enrichment::TitleNormalizer.call(t), cp.to_s ]
      end
      keys.uniq.count { |k| k != [ "", "" ] }
    end
  end
end
