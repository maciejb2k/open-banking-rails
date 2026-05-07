# frozen_string_literal: true

module Resources
  class TransactionSyncs < Grape::API
    KIND = "transaction_sync"

    before { authenticate! }

    resource :transaction_syncs do
      desc "List transaction-sync runs" do
        success model: Entities::OperationRun, is_array: true
      end
      params do
        optional :status, type: String
        optional :page,   type: Integer
        optional :limit,  type: Integer
      end
      get do
        scope = ::OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id).includes(:subject)
        scope = scope.where(status: params[:status]) if params[:status].present?

        pagy_obj, rows = paginate(scope.order(created_at: :desc))
        present :data, rows, with: Entities::OperationRun
        present :pagination, pagination_meta(pagy_obj)
      end

      desc "Queue a new transaction sync" do
        success model: Entities::OperationRun
      end
      params do
        optional :bank_connection_id, type: Integer, desc: "Sync a single connection; omit for all"
        optional :date_from,          type: Date
        optional :date_to,            type: Date
      end
      post do
        result = ::TransactionSyncs::Queuer.call(
          user:  current_user,
          input: ::TransactionSyncs::Queuer::Input.new(
            bank_connection_id: params[:bank_connection_id],
            date_from:          params[:date_from],
            date_to:             params[:date_to]
          )
        )
        if result.success?
          status 201
          present result.run, with: Entities::OperationRun
        else
          error!({ message: result.error, details: Array(result.error_messages) }, 422)
        end
      end

      route_param :id, type: Integer do
        desc "Fetch a sync run" do
          success model: Entities::OperationRun
        end
        get do
          run = ::OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id)
                              .includes(:subject).find(params[:id])
          present run, with: Entities::OperationRun
        end
      end
    end
  end
end
