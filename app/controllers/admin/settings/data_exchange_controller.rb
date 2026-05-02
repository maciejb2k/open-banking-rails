# frozen_string_literal: true

module Admin
  module Settings
    # Per-user export/import of domain data. Sits next to Preferences in the
    # settings nav and reuses its sectioned layout — but lives in its own
    # controller because the file-upload + cipher flow has nothing in common
    # with the field-grouped preference forms.
    #
    # Thin pipe by design — all real work (validation, OperationRun
    # lifecycle, multi-tenant scoping, cipher, transaction boundary) lives
    # in DataExchange::Operations::*. The controller just gathers params,
    # calls the operation, and chooses between send_data / redirect.
    class DataExchangeController < BaseController
      def show
        @available_resources = DataExchange::Registry.all_keys.to_h do |key|
          klass = DataExchange::Registry.fetch(key)
          [ key, klass.new(user: current_user).scope_for_export.count ]
        end
      end

      def export
        result = DataExchange::Operations::Export.call(
          user:          current_user,
          resource_keys: DataExchange::Registry.all_keys,
          passphrase:    params[:passphrase].to_s
        )

        send_data result.blob,
                  filename: bundle_filename,
                  type: "application/octet-stream",
                  disposition: "attachment"
      rescue DataExchange::Operations::Export::Failed => e
        redirect_to admin_settings_preferences_data_exchange_path,
                    alert: "Export failed: #{e.message}"
      end

      def import
        if params[:bundle].blank?
          redirect_to admin_settings_preferences_data_exchange_path,
                      alert: "Bundle file is required."
          return
        end

        result = DataExchange::Operations::Import.call(
          user:        current_user,
          bundle_blob: params[:bundle].read,
          passphrase:  params[:passphrase].to_s,
          strategy:    (params[:strategy].presence || "skip_existing").to_sym
        )

        redirect_to admin_settings_preferences_data_exchange_path,
                    notice: "Import done — #{result.imported} imported, " \
                            "#{result.updated} updated, #{result.skipped} skipped."
      rescue DataExchange::Operations::Import::Failed => e
        redirect_to admin_settings_preferences_data_exchange_path,
                    alert: "Import failed: #{e.message}"
      end

      private

      def bundle_filename
        "obr-export-#{Time.current.utc.strftime('%Y%m%d-%H%M%S')}.obrbundle"
      end
    end
  end
end
