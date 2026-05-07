# frozen_string_literal: true

module Resources
  class Transactions < Grape::API
    before { authenticate! }

    resource :transactions do
      desc "List ledger entries (bank + manual) with filters and pagination" do
        success model: Entities::LedgerEntry, is_array: true
      end
      params do
        optional :from,           type: Date,    desc: "Booking date >= (ISO 8601)"
        optional :to,             type: Date,    desc: "Booking date <= (ISO 8601)"
        optional :direction,      type: String,  values: %w[credit debit]
        optional :status,         type: String,  values: %w[booked pending]
        optional :account_id,     type: Integer
        optional :merchant_id,    type: Integer
        optional :category_id,    type: Integer
        optional :category_path,  type: String,  desc: "ltree prefix; matches descendants"
        optional :payment_method, type: String
        optional :currency,       type: String
        optional :source_type,    type: String,  values: %w[BankTransaction ManualTransaction]
        optional :page,           type: Integer
        optional :limit,          type: Integer
      end
      get do
        scope = LedgerEntry.for_user(current_user)
        scope = scope.where(booking_date: params[:from]..) if params[:from]
        scope = scope.where(booking_date: ..params[:to])   if params[:to]
        scope = scope.where(direction: params[:direction]) if params[:direction]
        scope = scope.where(status: params[:status])       if params[:status]
        scope = scope.where(bank_account_id: params[:account_id])      if params[:account_id]
        scope = scope.where(merchant_id: params[:merchant_id])         if params[:merchant_id]
        scope = scope.where(effective_category_id: params[:category_id]) if params[:category_id]
        scope = scope.under_path(params[:category_path]) if params[:category_path]
        scope = scope.where(payment_method: params[:payment_method])   if params[:payment_method]
        scope = scope.where(currency: params[:currency].to_s.upcase)   if params[:currency]
        scope = scope.where(source_type: params[:source_type])         if params[:source_type]

        pagy_obj, rows = paginate(scope.order(booking_date: :desc, source_id: :desc))
        present :data, rows, with: Entities::LedgerEntry
        present :pagination, pagination_meta(pagy_obj)
      end

      desc "Fetch a single ledger entry by source type + id" do
        success model: Entities::LedgerEntry
      end
      params do
        requires :source_type, type: String, values: %w[BankTransaction ManualTransaction]
        requires :source_id,   type: Integer
      end
      route_param :source_type do
        route_param :source_id do
          get do
            entry = LedgerEntry.for_user(current_user)
                               .find_by!(source_type: params[:source_type], source_id: params[:source_id])
            present entry, with: Entities::LedgerEntry
          end
        end
      end
    end
  end
end
