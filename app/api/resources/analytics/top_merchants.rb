# frozen_string_literal: true

module Resources
  module Analytics
    class TopMerchants < Grape::API
      before { authenticate! }

      namespace :analytics do
        desc "Top spend merchants for the period"
        params do
          optional :from,         type: Date
          optional :to,           type: Date
          optional :currency,     type: String
          optional :account_ids,  type: Array[Integer], coerce_with: ->(v) { Array(v).map(&:to_i) }
          optional :under_path,   type: String
          optional :limit,        type: Integer, default: 10
        end
        get :top_merchants do
          filter = ::Analytics::Filter.new(user: current_user, params: params)
          rows   = ::Analytics::TopMerchants.call(
            filter.scope, user: current_user, currency: filter.currency, limit: params[:limit]
          )

          {
            currency: filter.currency,
            period:   { from: filter.period.from, to: filter.period.to },
            rows: rows.map { |r|
              merchant = r.merchant
              {
                merchant: {
                  id:                  merchant.id,
                  name:                merchant.name,
                  slug:                merchant.slug,
                  default_category_id: merchant.default_category_id
                },
                amount_cents: r.amount_cents,
                count:        r.count
              }
            }
          }
        end
      end
    end
  end
end
