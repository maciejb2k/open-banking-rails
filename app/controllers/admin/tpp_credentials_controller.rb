# frozen_string_literal: true

module Admin
  class TppCredentialsController < BaseController
    before_action :set_credential, only: %i[show edit update destroy test_connection make_primary]

    def index
      @pagy, @collection = paginated(current_user.tpp_credentials, default_sort: "created_at desc")
    end

    def show
    end

    def new
      @credential = current_user.tpp_credentials.new(provider: "enable_banking", environment: "PRODUCTION")
    end

    def create
      first_credential = current_user.tpp_credentials.none?
      @credential = current_user.tpp_credentials.new(credential_params)
      @credential.primary = true if first_credential

      if @credential.save
        redirect_to admin_tpp_credential_path(@credential),
                    notice: "TPP credential created. Run \"Test connection\" to verify it works."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @credential.update(credential_params)
        redirect_to admin_tpp_credential_path(@credential), notice: "Updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @credential.bank_connections.exists?
        redirect_to admin_tpp_credential_path(@credential),
                    alert: "Cannot delete - credential has bank connections. Remove them first."
      else
        @credential.destroy
        redirect_to admin_tpp_credentials_path, notice: "Credential deleted."
      end
    end

    def test_connection
      result = EnableBanking::Operations::VerifyCredential.call(@credential)
      flash_key = result.failed? ? :alert : :notice
      redirect_to admin_tpp_credential_path(@credential), flash_key => result.message
    end

    def make_primary
      @credential.make_primary!
      redirect_to admin_tpp_credential_path(@credential),
                  notice: "#{@credential.name} is now the primary credential."
    end

    private

    def set_credential
      @credential = current_user.tpp_credentials.find(params[:id])
    end

    def credential_params
      params.expect(tpp_credential: %i[
        name provider environment redirect_url
        application_id private_key_pem public_cert_pem
      ])
    end
  end
end
