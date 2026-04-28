# frozen_string_literal: true

module Admin
  module Settings
    class BankConnectionsController < BaseController
      before_action :set_connection, only: %i[show edit update destroy refresh reauth]
      before_action :require_primary_credential, only: %i[new create]

      EB_STATUS_MAP = {
        "AUTHORIZED" => "authorized",
        "CLOSED" => "closed",
        "EXPIRED" => "expired",
        "REJECTED" => "revoked",
        "REVOKED" => "revoked"
      }.freeze

      def index
        scope = BankConnection.joins(:tpp_credential).where(tpp_credentials: { user_id: current_user.id })
        @q = scope.ransack(params[:q])
        @q.sorts = "valid_until asc" if @q.sorts.empty?
        @pagy, @collection = pagy(:offset, @q.result.includes(:tpp_credential))
      end

      def show
      end

      def edit
      end

      def update
        if @connection.update(connection_params)
          redirect_to admin_settings_bank_connection_path(@connection), notice: "Updated."
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

        result = EnableBanking::Queries::ListAspsps.call(credential: @primary_credential, country: @form.aspsp_country)
        if result.success?
          @aspsps = Array(result.data["aspsps"]).sort_by { |a| a["name"].to_s.downcase }
        else
          redirect_to admin_settings_bank_connections_path,
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

        state_token = EnableBanking::State.encode(
          user_id: current_user.id,
          tpp_credential_id: @primary_credential.id,
          aspsp_name: @form.aspsp_name,
          aspsp_country: @form.aspsp_country,
          psu_type: @form.psu_type,
          replaces_connection_id: @replaces_connection_id
        )

        result = EnableBanking::Queries::StartAuth.call(
          credential: @primary_credential,
          aspsp_name: @form.aspsp_name,
          aspsp_country: @form.aspsp_country,
          psu_type: @form.psu_type,
          state: state_token,
          valid_days: @form.valid_days
        )

        if result.success? && result.data["url"].present?
          redirect_to result.data["url"], allow_other_host: true, status: :see_other
        else
          redirect_to new_admin_settings_bank_connection_path,
                      alert: "Failed to start auth: #{result.error.presence || "HTTP #{result.status}"}"
        end
      rescue EnableBanking::Error => e
        redirect_to new_admin_settings_bank_connection_path,
                    alert: "Configuration error: #{e.message}"
      end

      def destroy
        # Best-effort: try to close on EB side before marking locally.
        if @connection.status == "authorized" && @connection.session_id.present?
          EnableBanking::Queries::CloseSession.call(
            credential: @connection.tpp_credential,
            session_id: @connection.session_id
          )
        end
        @connection.update!(status: "closed", closed_at: Time.current, last_error: nil)
        redirect_to admin_settings_bank_connections_path,
                    notice: "Connection closed."
      end

      def refresh
        result = EnableBanking::Queries::GetSession.call(
          credential: @connection.tpp_credential,
          session_id: @connection.session_id
        )

        if result.success?
          data = result.data
          @connection.update!(
            status: EB_STATUS_MAP.fetch(data["status"], "error"),
            last_refreshed_at: Time.current,
            access_balances: data.dig("access", "balances"),
            access_transactions: data.dig("access", "transactions"),
            valid_until: data.dig("access", "valid_until"),
            closed_at: data["closed"],
            last_error: nil
          )
          redirect_to admin_settings_bank_connection_path(@connection),
                      notice: "Refreshed — status: #{@connection.status}, valid until #{@connection.valid_until&.to_date}."
        else
          @connection.update!(last_error: "HTTP #{result.status}: #{result.error}")
          redirect_to admin_settings_bank_connection_path(@connection),
                      alert: "Refresh failed: #{result.error.presence || "HTTP #{result.status}"}"
        end
      rescue EnableBanking::Error => e
        redirect_to admin_settings_bank_connection_path(@connection),
                    alert: "Configuration error: #{e.message}"
      end

      def reauth
        redirect_to new_admin_settings_bank_connection_path(
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
        BankConnection.joins(:tpp_credential)
                      .where(tpp_credentials: { user_id: current_user.id })
                      .where(id: id).pick(:id)
      end

      def connection_params
        params.expect(bank_connection: [ :valid_until, :status ])
      end

      def require_primary_credential
        @primary_credential = current_user.primary_tpp_credential
        return if @primary_credential.present?

        redirect_to admin_settings_tpp_credentials_path,
                    alert: "Configure a primary TPP credential before connecting banks."
      end

      def set_connection
        @connection = BankConnection
                        .joins(:tpp_credential)
                        .where(tpp_credentials: { user_id: current_user.id })
                        .find(params[:id])
      end
    end
  end
end
