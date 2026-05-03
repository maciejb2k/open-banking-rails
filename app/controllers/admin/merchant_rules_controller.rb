# frozen_string_literal: true

module Admin
  class MerchantRulesController < BaseController
    before_action :set_merchant
    before_action :set_rule, only: %i[update destroy]

    def create
      @rule = @merchant.merchant_rules.build(rule_params.merge(user: current_user, source: "user", approved_at: Time.current, approved_by: current_user))
      if @rule.save
        Enrichment::TransactionEnricher.rebuild!(user: current_user)
        redirect_to admin_merchant_path(@merchant), notice: "Rule added - historical transactions re-classified."
      else
        redirect_to admin_merchant_path(@merchant), alert: "Could not add rule: #{@rule.errors.full_messages.join(', ')}"
      end
    end

    def update
      if @rule.update(rule_params)
        Enrichment::TransactionEnricher.rebuild!(user: current_user)
        redirect_to admin_merchant_path(@merchant), notice: "Rule updated."
      else
        redirect_to admin_merchant_path(@merchant), alert: "Could not update rule: #{@rule.errors.full_messages.join(', ')}"
      end
    end

    def destroy
      @rule.destroy
      Enrichment::TransactionEnricher.rebuild!(user: current_user)
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
