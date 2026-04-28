# frozen_string_literal: true

module Admin
  module Settings
    class TppCredentialsController < BaseController
      before_action :set_credential, only: %i[show edit update destroy test_connection make_primary]

      def index
        @q = current_user.tpp_credentials.ransack(params[:q])
        @q.sorts = "created_at desc" if @q.sorts.empty?
        @pagy, @collection = pagy(:offset, @q.result)
      end

      def show
      end

      def new
        @credential = current_user.tpp_credentials.new(provider: "enable_banking", environment: "PRODUCTION")
      end

      def create
        @credential = current_user.tpp_credentials.new(credential_params)
        @credential.primary = true if current_user.tpp_credentials.none?

        if @credential.save
          redirect_to admin_settings_tpp_credential_path(@credential),
                      notice: "TPP credential created. Run \"Test connection\" to verify it works."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @credential.update(credential_params)
          redirect_to admin_settings_tpp_credential_path(@credential), notice: "Updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @credential.bank_connections.exists?
          redirect_to admin_settings_tpp_credential_path(@credential),
                      alert: "Cannot delete — credential has bank connections. Remove them first."
        else
          @credential.destroy
          redirect_to admin_settings_tpp_credentials_path, notice: "Credential deleted."
        end
      end

      def test_connection
        result = EnableBanking::Queries::GetApplication.call(credential: @credential)

        if result.success?
          updates = {
            status: "active",
            last_verified_at: Time.current,
            last_verification_error: nil,
            metadata: result.data
          }

          msg_parts = [ "Connection verified — metadata refreshed." ]
          registered = Array(result.data["redirect_urls"])

          if registered.any? && !registered.include?(@credential.redirect_url)
            if registered.size == 1
              # Only one URL registered — safe to auto-sync, no ambiguity.
              updates[:redirect_url] = registered.first
              msg_parts << "Local redirect_url updated to match EB: #{registered.first}"
            else
              # Multiple URLs — user must pick. Warn, don't auto-change.
              msg_parts << "⚠ Local redirect_url (#{@credential.redirect_url}) is NOT in EB list. Choose one of: #{registered.join(", ")}"
            end
          end

          @credential.update!(updates)
          redirect_to admin_settings_tpp_credential_path(@credential), notice: msg_parts.join(" ")
        else
          @credential.update!(
            status: "error",
            last_verification_error: "HTTP #{result.status}: #{result.error}"
          )
          redirect_to admin_settings_tpp_credential_path(@credential),
                      alert: "Test failed: #{result.error.presence || "HTTP #{result.status}"}"
        end
      rescue EnableBanking::Error => e
        @credential.update!(status: "error", last_verification_error: e.message)
        redirect_to admin_settings_tpp_credential_path(@credential),
                    alert: "Configuration error: #{e.message}"
      end

      def make_primary
        @credential.make_primary!
        redirect_to admin_settings_tpp_credential_path(@credential),
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
end
