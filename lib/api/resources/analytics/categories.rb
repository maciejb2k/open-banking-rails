# frozen_string_literal: true

module Resources
  module Analytics
    class Categories < Grape::API
      before { authenticate! }

      namespace :analytics do
        resource :categories do
          desc "Per-category drilldown - merchants in this category for the period"
          params do
            requires :slug,        type: String
            optional :from,        type: Date
            optional :to,          type: Date
            optional :currency,    type: String
            optional :account_ids, type: Array[Integer], coerce_with: ->(v) { Array(v).map(&:to_i) }
          end
          route_param :slug do
            get do
              category = current_user.categories.find_by!(slug: params[:slug])
              filter   = ::Analytics::Filter.new(user: current_user, params: params)

              merchants = ::Analytics::SpendBreakdown.by_merchant_in_category(
                filter.scope, category, user: current_user, currency: filter.currency
              )
              subtree = if category.descendants.any?
                ::Analytics::SpendBreakdown.by_subpath(
                  filter.scope, under: category, user: current_user, currency: filter.currency
                )
              else
                []
              end

              {
                category: {
                  id:   category.id,
                  name: category.name,
                  slug: category.slug,
                  path: category.path.to_s,
                  kind: category.kind
                },
                currency:    filter.currency,
                period:      { from: filter.period.from, to: filter.period.to },
                total_cents: merchants.sum(&:amount_cents),
                merchants: merchants.map { |r|
                  {
                    merchant: r.merchant ? { id: r.merchant.id, name: r.merchant.name, slug: r.merchant.slug } : nil,
                    amount_cents: r.amount_cents,
                    count:        r.count
                  }
                },
                subtree: subtree.map { |r|
                  { path: r.path.to_s, slug: r.slug, name: r.name, amount_cents: r.amount_cents, count: r.count }
                }
              }
            end
          end
        end
      end
    end
  end
end
