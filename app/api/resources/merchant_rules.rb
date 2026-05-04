# frozen_string_literal: true

module Resources
  class MerchantRules < Grape::API
    before { authenticate! }

    resource :merchants do
      route_param :merchant_id, type: Integer do
        resource :rules do
          helpers do
            def load_merchant!
              current_user.merchants.find(params[:merchant_id])
            end
          end

          desc "List rules for a merchant" do
            success model: Entities::MerchantRule, is_array: true
          end
          get do
            present load_merchant!.merchant_rules.order(:source, priority: :desc),
                    with: Entities::MerchantRule
          end

          desc "Add a rule to a merchant" do
            success model: Entities::MerchantRule
          end
          params do
            requires :kind,           type: String, values: %w[contains equals regex starts_with ends_with]
            requires :field,          type: String, values: %w[title counterparty_name counterparty_iban]
            requires :pattern,        type: String
            optional :case_sensitive, type: Boolean, default: false
            optional :priority,       type: Integer, default: 0
            optional :enabled,        type: Boolean, default: true
          end
          post do
            result = ::MerchantRules::Creator.call(
              merchant:   load_merchant!,
              actor:      current_user,
              attributes: declared(params, include_missing: false).except("merchant_id")
            )
            if result.success?
              status 201
              present result.rule, with: Entities::MerchantRule
            else
              error!({ message: result.error, details: Array(result.error_messages) }, 422)
            end
          end

          route_param :id, type: Integer do
            helpers do
              def load_rule!
                load_merchant!.merchant_rules.find(params[:id])
              end
            end

            desc "Update a rule" do
              success model: Entities::MerchantRule
            end
            params do
              optional :kind,           type: String, values: %w[contains equals regex starts_with ends_with]
              optional :field,          type: String, values: %w[title counterparty_name counterparty_iban]
              optional :pattern,        type: String
              optional :case_sensitive, type: Boolean
              optional :priority,       type: Integer
              optional :enabled,        type: Boolean
            end
            patch do
              result = ::MerchantRules::Updater.call(
                rule:       load_rule!,
                actor:      current_user,
                attributes: declared(params, include_missing: false).except("merchant_id", "id")
              )
              if result.success?
                present result.rule, with: Entities::MerchantRule
              else
                error!({ message: result.error, details: Array(result.error_messages) }, 422)
              end
            end

            desc "Delete a rule"
            delete do
              ::MerchantRules::Destroyer.call(rule: load_rule!, actor: current_user)
              status 204
              ""
            end
          end
        end
      end
    end
  end
end
