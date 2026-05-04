# frozen_string_literal: true

module Resources
  module Analytics
    class Merchants < Grape::API
      before { authenticate! }

      namespace :analytics do
        resource :merchants do
          desc "Per-merchant drilldown - transactions, monthly trend, totals"
          params do
            requires :slug,        type: String
            optional :from,        type: Date
            optional :to,          type: Date
            optional :currency,    type: String
            optional :account_ids, type: Array[Integer], coerce_with: ->(v) { Array(v).map(&:to_i) }
            optional :page,        type: Integer
            optional :limit,       type: Integer
          end
          route_param :slug do
            get do
              merchant = current_user.merchants.find_by!(slug: params[:slug])
              filter   = ::Analytics::Filter.new(user: current_user, params: params)

              spend_scope = filter.scope.spend.where(merchant_id: merchant.id)
              total_cents = spend_scope.sum(:amount_cents)
              count       = spend_scope.count

              tx_scope = spend_scope.includes(:effective_category).order(booking_date: :desc)
              pagy_obj, transactions = paginate(tx_scope)

              monthly = ::Analytics::SpendBreakdown.merchant_monthly_trend(
                user: current_user, merchant_id: merchant.id, currency: filter.currency
              )

              {
                merchant: {
                  id:                  merchant.id,
                  name:                merchant.name,
                  slug:                merchant.slug,
                  default_category_id: merchant.default_category_id
                },
                currency:    filter.currency,
                period:      { from: filter.period.from, to: filter.period.to },
                total_cents: total_cents,
                count:       count,
                monthly_trend: monthly.map { |r|
                  { period: r.respond_to?(:period) ? r.period : nil, amount_cents: r.amount_cents, count: r.count }
                },
                transactions: ::Entities::LedgerEntry.represent(transactions).as_json,
                pagination:   pagination_meta(pagy_obj)
              }
            end
          end
        end
      end
    end
  end
end
