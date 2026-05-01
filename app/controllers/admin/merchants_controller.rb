# frozen_string_literal: true

module Admin
  class MerchantsController < BaseController
    before_action :set_merchant, only: %i[show edit update destroy archive unarchive approve]

    def index
      scope = current_user.merchants.includes(:default_category, :merchant_rules)
      scope = scope.active unless params[:show_archived] == "1"
      scope = scope.where(source: params[:source]) if params[:source].present?
      scope = scope.where(default_category_id: params[:category_id]) if params[:category_id].present?
      scope = scope.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?

      @pagy, @collection = pagy(:offset, scope.order(:name))
      # Counts the user's own transactions only — joining through the
      # enrichable polymorphic onto bank_transactions / manual_transactions
      # would be more correct, but for the merchant index "tx using this
      # merchant" within scope is enough; cross-user merchants don't exist
      # any more so the count is naturally bounded.
      @transaction_counts = TransactionEnrichment
                              .where(merchant_id: @collection.map(&:id))
                              .group(:merchant_id).count
    end

    def show
      # Same shape as bank/cash tx show + analytics drill-downs: a merchant
      # tied to a hidden category leaks the category itself + N transactions
      # in the recent list. Bounce; user has to remove the category from
      # the hidden list in /admin/settings/preferences to inspect.
      if current_user.hides_category?(@merchant.default_category_id)
        redirect_to admin_merchants_path,
                    alert: "This merchant is in a hidden category. Remove it from the hidden list in preferences to open it."
        return
      end

      @rules = @merchant.merchant_rules.order(:source, priority: :desc)
      @transaction_count = TransactionEnrichment.where(merchant_id: @merchant.id).count
      @recent_transactions = BankTransaction
                               .joins(:enrichment)
                               .where(transaction_enrichments: { merchant_id: @merchant.id })
                               .includes(:bank_account)
                               .order(booking_date: :desc).limit(10)
      @new_rule = @merchant.merchant_rules.build(field: "title", kind: "contains", source: "user", enabled: true)
    end

    def edit
      return unless current_user.hides_category?(@merchant.default_category_id)

      redirect_to admin_merchants_path,
                  alert: "This merchant is in a hidden category. Remove it from the hidden list in preferences to edit it."
    end

    def new
      @merchant = Merchant.new(source: "user", kind: "company")
    end

    def create
      @merchant = current_user.merchants.new(merchant_params.merge(source: "user", approved_at: Time.current, approved_by: current_user))
      @merchant.slug = generate_slug(@merchant.name) if @merchant.slug.blank?
      if @merchant.save
        redirect_to admin_merchant_path(@merchant), notice: "Merchant created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      old_default_category_id = @merchant.default_category_id
      if @merchant.update(merchant_params)
        # If the default category changed, transactions enriched against this
        # merchant inherit the new category through `effective_category` —
        # no DB write needed. We log it for clarity in audit.
        if @merchant.default_category_id != old_default_category_id
          Rails.logger.info("[Merchant##{@merchant.id}] default_category #{old_default_category_id} -> #{@merchant.default_category_id} — propagated via effective_category")
        end
        redirect_to safe_return_to(default: admin_merchant_path(@merchant)), notice: "Merchant updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if TransactionEnrichment.where(merchant_id: @merchant.id).exists?
        redirect_to admin_merchant_path(@merchant),
                    alert: "Can't delete — this merchant has linked transactions. Archive it instead."
      else
        @merchant.destroy
        redirect_to safe_return_to(default: admin_merchants_path), notice: "Merchant deleted."
      end
    end

    def archive
      @merchant.update!(archived_at: Time.current)
      redirect_to safe_return_to(default: admin_merchants_path), notice: "Merchant archived."
    end

    def unarchive
      @merchant.update!(archived_at: nil)
      redirect_to safe_return_to(default: admin_merchant_path(@merchant)), notice: "Merchant restored."
    end

    # Approves an LLM-proposed merchant: flips its rules to `enabled: true`,
    # marks the merchant as approved, and rebuilds enrichments so any
    # historical match is applied retroactively.
    def approve
      ActiveRecord::Base.transaction do
        @merchant.update!(approved_at: Time.current, approved_by: current_user)
        @merchant.merchant_rules.where(source: "llm", enabled: false).each do |rule|
          rule.update!(enabled: true, approved_at: Time.current, approved_by: current_user)
        end
      end
      Enrichment::TransactionEnricher.rebuild!(user: current_user)
      redirect_to safe_return_to(default: admin_merchant_path(@merchant)),
                  notice: "Approved — historical transactions re-classified."
    end

    private

    def set_merchant
      @merchant = current_user.merchants.find(params[:id])
    end

    def merchant_params
      params.expect(merchant: %i[name slug kind default_category_id logo_url notes])
    end

    def generate_slug(name)
      base = name.to_s.downcase.gsub(/\p{M}/, "").gsub(/[^a-z0-9]+/, "_").gsub(/_+/, "_").gsub(/\A_|_\z/, "")
      candidate = base
      i = 2
      while current_user.merchants.exists?(slug: candidate)
        candidate = "#{base}_#{i}"
        i += 1
      end
      candidate
    end
  end
end
