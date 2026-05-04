# frozen_string_literal: true

module Resources
  class BankAccounts < Grape::API
    before { authenticate! }

    resource :bank_accounts do
      desc "List bank accounts (synced + manual cash wallets)" do
        success model: Entities::BankAccount, is_array: true
      end
      params do
        optional :manual, type: Boolean, desc: "true → only cash wallets, false → only synced"
        optional :page,   type: Integer
        optional :limit,  type: Integer
      end
      get do
        scope = ::BankAccount.where(id: current_user.all_bank_account_ids)
        scope = scope.where(manual: params[:manual]) if params.key?(:manual) && !params[:manual].nil?

        pagy_obj, rows = paginate(scope.order(:created_at))
        present :data, rows, with: Entities::BankAccount
        present :pagination, pagination_meta(pagy_obj)
      end

      route_param :id, type: Integer do
        helpers do
          def load_account!
            ::BankAccount.where(id: current_user.all_bank_account_ids).find(params[:id])
          end
        end

        desc "Fetch a bank account" do
          success model: Entities::BankAccount
        end
        get do
          present load_account!, with: Entities::BankAccount
        end

        desc "Refresh account details from the AISP provider" do
          success model: Entities::BankAccount
          failure [ [ 422, "Refresh failed" ] ]
        end
        post :refresh_details do
          account = load_account!
          ::EnableBanking::Operations::RefreshAccountDetails.call(account)
          present account.reload, with: Entities::BankAccount
        rescue ::EnableBanking::Operations::RefreshAccountDetails::Failed => e
          error!({ message: "Refresh failed: #{e.message}" }, 422)
        end

        desc "Refresh balances from the AISP provider" do
          success model: Entities::BankAccount
          failure [ [ 422, "Refresh failed" ] ]
        end
        post :refresh_balances do
          account = load_account!
          ::EnableBanking::Operations::RefreshAccountBalances.call(account)
          present account.reload, with: Entities::BankAccount
        rescue ::EnableBanking::Operations::RefreshAccountBalances::Failed => e
          error!({ message: "Refresh failed: #{e.message}" }, 422)
        end
      end
    end
  end
end
