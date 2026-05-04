# frozen_string_literal: true

module Resources
  class TppCredentials < Grape::API
    before { authenticate! }

    resource :tpp_credentials do
      desc "List TPP credentials" do
        success model: Entities::TppCredential, is_array: true
      end
      params do
        optional :page,  type: Integer
        optional :limit, type: Integer
      end
      get do
        pagy_obj, rows = paginate(current_user.tpp_credentials.order(created_at: :desc))
        present :data, rows, with: Entities::TppCredential
        present :pagination, pagination_meta(pagy_obj)
      end

      desc "Create a TPP credential" do
        success model: Entities::TppCredential
      end
      params do
        requires :name,            type: String
        optional :provider,        type: String, default: "enable_banking"
        optional :environment,     type: String, default: "PRODUCTION"
        optional :redirect_url,    type: String
        optional :application_id,  type: String
        optional :private_key_pem, type: String
        optional :public_cert_pem, type: String
      end
      post do
        attrs = declared(params, include_missing: false).symbolize_keys
        credential = current_user.tpp_credentials.new(attrs)
        credential.primary = true if current_user.tpp_credentials.none?
        credential.save!
        status 201
        present credential, with: Entities::TppCredential
      end

      route_param :id, type: Integer do
        helpers do
          def load_credential!
            current_user.tpp_credentials.find(params[:id])
          end
        end

        desc "Fetch a credential" do
          success model: Entities::TppCredential
        end
        get do
          present load_credential!, with: Entities::TppCredential
        end

        desc "Update a credential" do
          success model: Entities::TppCredential
        end
        params do
          optional :name,            type: String
          optional :provider,        type: String
          optional :environment,     type: String
          optional :redirect_url,    type: String
          optional :application_id,  type: String
          optional :private_key_pem, type: String
          optional :public_cert_pem, type: String
        end
        patch do
          credential = load_credential!
          credential.update!(declared(params, include_missing: false).symbolize_keys.except(:id))
          present credential, with: Entities::TppCredential
        end

        desc "Delete a credential (only when no bank connections reference it)"
        delete do
          credential = load_credential!
          if credential.bank_connections.exists?
            error!({ message: "Cannot delete - credential has bank connections. Remove them first." }, 422)
          end
          credential.destroy!
          status 204
          ""
        end

        desc "Verify the credential against the provider" do
          success model: Entities::TppCredential
        end
        post :test_connection do
          credential = load_credential!
          result = ::EnableBanking::Operations::VerifyCredential.call(credential)
          if result.failed?
            error!({ message: result.message }, 422)
          else
            present credential.reload, with: Entities::TppCredential
          end
        end

        desc "Mark this credential as primary" do
          success model: Entities::TppCredential
        end
        post :make_primary do
          credential = load_credential!
          credential.make_primary!
          present credential, with: Entities::TppCredential
        end
      end
    end
  end
end
