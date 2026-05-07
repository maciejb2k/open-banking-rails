# frozen_string_literal: true

module Resources
  class BankConnections < Grape::API
    before { authenticate! }

    resource :bank_connections do
      desc "List bank connections" do
        success model: Entities::BankConnection, is_array: true
      end
      params do
        optional :status, type: String
        optional :page,   type: Integer
        optional :limit,  type: Integer
      end
      get do
        scope = ::BankConnection.for_user(current_user).includes(:tpp_credential)
        scope = scope.where(status: params[:status]) if params[:status].present?

        pagy_obj, rows = paginate(scope.order(valid_until: :asc))
        present :data, rows, with: Entities::BankConnection
        present :pagination, pagination_meta(pagy_obj)
      end

      route_param :id, type: Integer do
        helpers do
          def load_connection!
            ::BankConnection.for_user(current_user).find(params[:id])
          end
        end

        desc "Fetch a bank connection" do
          success model: Entities::BankConnection
        end
        get do
          present load_connection!, with: Entities::BankConnection
        end

        desc "Update editable fields" do
          success model: Entities::BankConnection
        end
        params do
          optional :valid_until, type: DateTime
          optional :status,      type: String
        end
        patch do
          connection = load_connection!
          connection.update!(declared(params, include_missing: false).symbolize_keys.except(:id))
          present connection, with: Entities::BankConnection
        end

        desc "Refresh status from the provider" do
          success model: Entities::BankConnection
          failure [ [ 422, "Refresh failed" ] ]
        end
        post :refresh do
          connection = load_connection!
          ::EnableBanking::Operations::RefreshConnection.call(connection)
          present connection.reload, with: Entities::BankConnection
        rescue ::EnableBanking::Operations::RefreshConnection::Failed => e
          error!({ message: "Refresh failed: #{e.message}" }, 422)
        end

        desc "Close a connection at the provider" do
          success model: Entities::BankConnection
        end
        delete do
          connection = load_connection!
          ::EnableBanking::Operations::CloseConnection.call(connection)
          present connection.reload, with: Entities::BankConnection
        end
      end
    end
  end
end
