# frozen_string_literal: true

module Admin
  class BankConnectionsController < BaseController
    before_action :set_connection, only: %i[show edit update destroy refresh reauth]
    before_action :require_primary_credential, only: %i[new create]

    def index
      @pagy, @collection = paginated(BankConnection.for_user(current_user), default_sort: "valid_until asc", includes: :tpp_credential)
    end

    def show
    end

    def edit
    end

    def update
      if @connection.update(connection_params)
        redirect_to admin_bank_connection_path(@connection), notice: "Updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def new
      @form = BankConnectionRequestForm.new(
        aspsp_name: params[:aspsp_name],
        aspsp_country: params[:aspsp_country].presence || "PL",
        psu_type: params[:psu_type].presence || "personal"
      )
      @replaces_connection_id = sanitize_replaces_param(params[:replaces])

      result = EnableBanking::Api::ListAspsps.call(credential: @primary_credential, country: @form.aspsp_country)
      if result.success?
        @aspsps = Array(result.data["aspsps"]).sort_by { |a| a["name"].to_s.downcase }
      else
        redirect_to admin_bank_connections_path,
                    alert: "Couldn't load bank list: #{result.error}"
      end
    end

    def create
      @form = BankConnectionRequestForm.new(form_params)
      @replaces_connection_id = sanitize_replaces_param(params[:replaces_connection_id])

      unless @form.valid?
        flash.now[:alert] = @form.errors.full_messages.join(", ")
        return new
      end

      url = EnableBanking::Operations::StartAuth.call(
        credential: @primary_credential,
        form: @form,
        current_user: current_user,
        replaces_connection_id: @replaces_connection_id
      )
      redirect_to url, allow_other_host: true, status: :see_other
    rescue EnableBanking::Operations::StartAuth::Failed => e
      redirect_to new_admin_bank_connection_path, alert: e.message
    end

    def destroy
      EnableBanking::Operations::CloseConnection.call(@connection)
      redirect_to admin_bank_connections_path, notice: "Connection closed."
    end

    def refresh
      EnableBanking::Operations::RefreshConnection.call(@connection)
      redirect_to admin_bank_connection_path(@connection),
                  notice: "Refreshed — status: #{@connection.status}, valid until #{@connection.valid_until&.to_date}."
    rescue EnableBanking::Operations::RefreshConnection::Failed => e
      redirect_to admin_bank_connection_path(@connection),
                  alert: "Refresh failed: #{e.message}"
    end

    def reauth
      redirect_to new_admin_bank_connection_path(
        aspsp_name: @connection.bank_name,
        aspsp_country: @connection.bank_country,
        psu_type: @connection.psu_type,
        replaces: @connection.id
      ), notice: "Re-authorize via the bank — the old connection will be marked as replaced when the new one is approved."
    end

    private

    def form_params
      params.fetch(:bank_connection_request_form, {}).permit(:aspsp_name, :aspsp_country, :psu_type, :valid_days)
    end

    # Only accept replaces_id that points to a connection owned by current_user.
    def sanitize_replaces_param(value)
      return nil if value.blank?
      id = value.to_i
      return nil if id.zero?
      BankConnection.for_user(current_user).where(id: id).pick(:id)
    end

    def connection_params
      params.expect(bank_connection: [ :valid_until, :status ])
    end

    def require_primary_credential
      @primary_credential = current_user.primary_tpp_credential
      return if @primary_credential.present?

      redirect_to admin_tpp_credentials_path,
                  alert: "Configure a primary TPP credential before connecting banks."
    end

    def set_connection
      @connection = BankConnection.for_user(current_user).find(params[:id])
    end
  end
end
