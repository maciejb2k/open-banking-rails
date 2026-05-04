# frozen_string_literal: true

module Resources
  module Analytics
    class CashFlow < Grape::API
      before { authenticate! }

      namespace :analytics do
        desc "Cash flow time-series + totals for the requested period"
        params do
          optional :from,         type: Date
          optional :to,           type: Date
          optional :bucket,       type: String, values: %w[day week month]
          optional :currency,     type: String
          optional :account_ids,  type: Array[Integer], coerce_with: ->(v) { Array(v).map(&:to_i) }
          optional :under_path,   type: String, desc: "ltree prefix to narrow the scope"
        end
        get :cash_flow do
          filter = ::Analytics::Filter.new(user: current_user, params: params)
          totals = ::Analytics::CashFlow.totals(filter.scope)
          series = ::Analytics::CashFlow.series(filter.scope, period: filter.period, currency: filter.currency)

          {
            currency: filter.currency,
            period: { from: filter.period.from, to: filter.period.to, bucket: filter.period.bucket },
            totals: {
              spend_cents:  totals[:spend_cents],
              income_cents: totals[:income_cents],
              net_cents:    totals[:net_cents]
            },
            series: series.map { |p|
              { date: p.date, spend_cents: p.spend_cents, income_cents: p.income_cents, net_cents: p.net_cents }
            }
          }
        end
      end
    end
  end
end
