# frozen_string_literal: true

module Resources
  module Analytics
    class Spend < Grape::API
      before { authenticate! }

      namespace :analytics do
        desc "Spend breakdown by category path"
        params do
          optional :from,         type: Date
          optional :to,           type: Date
          optional :bucket,       type: String, values: %w[day week month]
          optional :currency,     type: String
          optional :account_ids,  type: Array[Integer], coerce_with: ->(v) { Array(v).map(&:to_i) }
          optional :under_path,   type: String
          optional :depth,        type: Integer, desc: "nil = leaf rows, 1 = top level, 2 = mid level"
        end
        get :spend do
          filter = ::Analytics::Filter.new(user: current_user, params: params)
          rows   = ::Analytics::SpendBreakdown.by_category(
            filter.scope,
            user:           current_user,
            currency:       filter.currency,
            depth:          params[:depth],
            previous_scope: filter.previous_scope
          )

          {
            currency:    filter.currency,
            period:      { from: filter.period.from, to: filter.period.to, bucket: filter.period.bucket },
            total_cents: rows.sum(&:amount_cents),
            rows: rows.map { |r|
              {
                path:              r.path.to_s,
                slug:              r.slug,
                name:              r.name,
                amount_cents:      r.amount_cents,
                prev_amount_cents: r.prev_amount_cents,
                count:             r.count,
                delta_pct:         r.delta_pct
              }
            }
          }
        end
      end
    end
  end
end
