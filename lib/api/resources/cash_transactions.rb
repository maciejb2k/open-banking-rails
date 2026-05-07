# frozen_string_literal: true

module Resources
  class CashTransactions < Grape::API
    before { authenticate! }

    resource :cash_transactions do
      desc "List manual transactions" do
        success model: Entities::ManualTransaction, is_array: true
      end
      params do
        optional :wallet_id,  type: Integer
        optional :direction,  type: String, values: %w[credit debit]
        optional :from,       type: Date
        optional :to,         type: Date
        optional :page,       type: Integer
        optional :limit,      type: Integer
      end
      get do
        scope = ManualTransaction.for_user(current_user)
        scope = scope.where(bank_account_id: params[:wallet_id]) if params[:wallet_id]
        scope = scope.where(direction: params[:direction])       if params[:direction]
        scope = scope.where(booking_date: params[:from]..)       if params[:from]
        scope = scope.where(booking_date: ..params[:to])         if params[:to]

        pagy_obj, rows = paginate(scope.order(booking_date: :desc, id: :desc).includes(enrichment: %i[merchant category]))
        present :data, rows, with: Entities::ManualTransaction
        present :pagination, pagination_meta(pagy_obj)
      end

      desc "Create a manual cash transaction" do
        success model: Entities::ManualTransaction
        failure [ [ 422, "Validation error" ] ]
      end
      params do
        requires :amount,            type: String, desc: "e.g. '12.50'"
        optional :currency,          type: String, default: "PLN"
        optional :direction,         type: String, values: %w[credit debit], default: "debit"
        optional :booking_date,      type: Date
        optional :transaction_date,  type: Date
        optional :title,             type: String
        optional :note,              type: String
        optional :counterparty_name, type: String
        optional :merchant_id,       type: Integer
        optional :category_id,       type: Integer
        optional :payment_method,    type: String
      end
      post do
        result = ::Cash::TransactionCreator.call(
          user:  current_user,
          input: ::Cash::TransactionCreator::Input.new(declared(params, include_missing: false).symbolize_keys)
        )
        if result.success?
          status 201
          present result.transaction, with: Entities::ManualTransaction
        else
          error!({ message: result.error, details: Array(result.error_messages) }, 422)
        end
      end

      route_param :id, type: Integer do
        helpers do
          def load_manual!
            tx = ManualTransaction.for_user(current_user).find(params[:id])
            error!({ message: "This transaction was auto-generated and isn't editable here." }, 422) unless tx.source == "manual"
            tx
          end
        end

        desc "Fetch a manual transaction" do
          success model: Entities::ManualTransaction
        end
        get do
          present ManualTransaction.for_user(current_user).find(params[:id]), with: Entities::ManualTransaction
        end

        desc "Update a manual transaction" do
          success model: Entities::ManualTransaction
        end
        params do
          optional :amount,            type: String
          optional :direction,         type: String, values: %w[credit debit]
          optional :booking_date,      type: Date
          optional :transaction_date,  type: Date
          optional :title,             type: String
          optional :note,              type: String
          optional :counterparty_name, type: String
          optional :merchant_id,       type: Integer
          optional :category_id,       type: Integer
          optional :payment_method,    type: String
        end
        patch do
          tx = load_manual!
          result = ::Cash::TransactionUpdater.call(
            transaction: tx,
            input: ::Cash::TransactionUpdater::Input.new(declared(params, include_missing: false).except("id").symbolize_keys)
          )
          if result.success?
            present tx.reload, with: Entities::ManualTransaction
          else
            error!({ message: result.error, details: Array(result.error_messages) }, 422)
          end
        end

        desc "Delete a manual transaction"
        delete do
          load_manual!.destroy!
          status 204
          ""
        end
      end
    end
  end
end
