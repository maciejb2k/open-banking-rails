# frozen_string_literal: true

module Resources
  class BankTransactions < Grape::API
    before { authenticate! }

    resource :bank_transactions do
      desc "List bank-synced transactions" do
        success model: Entities::BankTransaction, is_array: true
      end
      params do
        optional :account_id,        type: Integer
        optional :merchant_id,       type: Integer
        optional :category_id,       type: Integer
        optional :payment_method,    type: String
        optional :enrichment_source, type: String
        optional :from,              type: Date
        optional :to,                type: Date
        optional :page,              type: Integer
        optional :limit,             type: Integer
      end
      get do
        scope = ::BankTransaction.for_user(current_user)
        scope = scope.where(bank_account_id: params[:account_id]) if params[:account_id]
        scope = scope.where(payment_method: params[:payment_method]) if params[:payment_method]
        scope = scope.where(booking_date: params[:from]..) if params[:from]
        scope = scope.where(booking_date: ..params[:to])   if params[:to]
        if params[:merchant_id] || params[:category_id] || params[:enrichment_source]
          scope = scope.joins(:enrichment)
          scope = scope.where(transaction_enrichments: { merchant_id: params[:merchant_id] }) if params[:merchant_id]
          scope = scope.where(transaction_enrichments: { category_id: params[:category_id] }) if params[:category_id]
          scope = scope.where(transaction_enrichments: { source: params[:enrichment_source] }) if params[:enrichment_source]
        end

        pagy_obj, rows = paginate(scope.includes(enrichment: %i[merchant category]).order(booking_date: :desc))
        present :data, rows, with: Entities::BankTransaction
        present :pagination, pagination_meta(pagy_obj)
      end

      desc "Fetch a single bank transaction" do
        success model: Entities::BankTransaction
      end
      route_param :id, type: Integer do
        get do
          tx = ::BankTransaction.for_user(current_user).includes(enrichment: %i[merchant category]).find(params[:id])
          present tx, with: Entities::BankTransaction
        end
      end
    end
  end
end
