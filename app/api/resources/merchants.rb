# frozen_string_literal: true

module Resources
  class Merchants < Grape::API
    before { authenticate! }

    resource :merchants do
      desc "List merchants" do
        success model: Entities::Merchant, is_array: true
      end
      params do
        optional :q,               type: String, desc: "Name ILIKE %q%"
        optional :source,          type: String, values: %w[user llm seed]
        optional :category_id,     type: Integer, desc: "Filter by default_category_id"
        optional :include_archived, type: Boolean, default: false
        optional :page,            type: Integer
        optional :limit,           type: Integer
      end
      get do
        scope = current_user.merchants.includes(:default_category, :merchant_rules)
        scope = scope.active unless params[:include_archived]
        scope = scope.where(source: params[:source]) if params[:source]
        scope = scope.where(default_category_id: params[:category_id]) if params[:category_id]
        scope = scope.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?

        pagy_obj, rows = paginate(scope.order(:name))
        present :data, rows, with: Entities::Merchant
        present :pagination, pagination_meta(pagy_obj)
      end

      desc "Create a merchant" do
        success model: Entities::Merchant
      end
      params do
        requires :name,                type: String
        optional :slug,                type: String
        optional :kind,                type: String, values: %w[company person unknown], default: "company"
        optional :default_category_id, type: Integer
        optional :logo_url,            type: String
        optional :notes,               type: String
      end
      post do
        result = ::Merchants::Creator.call(
          user:       current_user,
          attributes: declared(params, include_missing: false)
        )
        if result.success?
          status 201
          present result.merchant, with: Entities::Merchant
        else
          error!({ message: result.error, details: Array(result.error_messages) }, 422)
        end
      end

      route_param :id, type: Integer do
        helpers do
          def load_merchant!
            current_user.merchants.find(params[:id])
          end
        end

        desc "Fetch a merchant" do
          success model: Entities::Merchant
        end
        get do
          present load_merchant!, with: Entities::Merchant
        end

        desc "Update a merchant" do
          success model: Entities::Merchant
        end
        params do
          optional :name,                type: String
          optional :slug,                type: String
          optional :kind,                type: String, values: %w[company person unknown]
          optional :default_category_id, type: Integer
          optional :logo_url,            type: String
          optional :notes,               type: String
        end
        patch do
          merchant = load_merchant!
          merchant.update!(declared(params, include_missing: false).symbolize_keys.except(:id))
          present merchant, with: Entities::Merchant
        end

        desc "Delete a merchant (only when no transactions reference it)"
        delete do
          merchant = load_merchant!
          if TransactionEnrichment.where(merchant_id: merchant.id).exists?
            error!({ message: "Can't delete - this merchant has linked transactions. Archive it instead." }, 422)
          end
          merchant.destroy!
          status 204
          ""
        end

        desc "Archive a merchant" do
          success model: Entities::Merchant
        end
        post :archive do
          merchant = load_merchant!
          merchant.update!(archived_at: Time.current)
          present merchant, with: Entities::Merchant
        end

        desc "Unarchive a merchant" do
          success model: Entities::Merchant
        end
        post :unarchive do
          merchant = load_merchant!
          merchant.update!(archived_at: nil)
          present merchant, with: Entities::Merchant
        end

        desc "Approve an LLM-suggested merchant (and enable its rules)" do
          success model: Entities::Merchant
        end
        post :approve do
          merchant = load_merchant!
          ::Merchants::Approver.call(merchant: merchant, actor: current_user)
          present merchant.reload, with: Entities::Merchant
        end
      end
    end
  end
end
