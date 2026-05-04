# frozen_string_literal: true

module Admin
  class MerchantRulesController < BaseController
    before_action :set_merchant
    before_action :set_rule, only: %i[update destroy]

    def create
      result = MerchantRules::Creator.call(merchant: @merchant, actor: current_user, attributes: rule_params)
      if result.success?
        redirect_to admin_merchant_path(@merchant), notice: "Rule added - historical transactions re-classified."
      else
        redirect_to admin_merchant_path(@merchant), alert: "Could not add rule: #{result.error}"
      end
    end

    def update
      result = MerchantRules::Updater.call(rule: @rule, actor: current_user, attributes: rule_params)
      if result.success?
        redirect_to admin_merchant_path(@merchant), notice: "Rule updated."
      else
        redirect_to admin_merchant_path(@merchant), alert: "Could not update rule: #{result.error}"
      end
    end

    def destroy
      MerchantRules::Destroyer.call(rule: @rule, actor: current_user)
      redirect_to admin_merchant_path(@merchant), notice: "Rule deleted - transactions re-classified."
    end

    private

    def set_merchant
      @merchant = current_user.merchants.find(params[:merchant_id])
    end

    def set_rule
      @rule = @merchant.merchant_rules.find(params[:id])
    end

    def rule_params
      params.expect(merchant_rule: %i[kind field pattern case_sensitive priority enabled])
    end
  end
end
