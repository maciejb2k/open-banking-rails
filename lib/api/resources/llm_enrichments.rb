# frozen_string_literal: true

module Resources
  class LlmEnrichments < Grape::API
    KIND = "llm_enrichment"

    before { authenticate! }

    resource :llm_enrichments do
      desc "List LLM enrichment runs" do
        success model: Entities::OperationRun, is_array: true
      end
      params do
        optional :status, type: String
        optional :page,   type: Integer
        optional :limit,  type: Integer
      end
      get do
        scope = ::OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id)
        scope = scope.where(status: params[:status]) if params[:status].present?

        pagy_obj, rows = paginate(scope.order(created_at: :desc))
        present :data, rows, with: Entities::OperationRun
        present :pagination, pagination_meta(pagy_obj)
      end

      desc "Queue a new LLM enrichment run" do
        success model: Entities::OperationRun
        failure [ [ 422, "LLM not configured" ] ]
      end
      params do
        optional :limit, type: Integer, desc: "Max distinct title groups to send to the LLM"
      end
      post do
        result = ::LlmEnrichments::Queuer.call(
          user:  current_user,
          input: ::LlmEnrichments::Queuer::Input.new(limit: params[:limit])
        )
        if result.success?
          status 201
          present result.run, with: Entities::OperationRun
        else
          error!({ message: result.error, details: Array(result.error_messages) }, 422)
        end
      end

      route_param :id, type: Integer do
        desc "Fetch an LLM enrichment run" do
          success model: Entities::OperationRun
        end
        get do
          run = ::OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id).find(params[:id])
          present run, with: Entities::OperationRun
        end
      end
    end
  end
end
