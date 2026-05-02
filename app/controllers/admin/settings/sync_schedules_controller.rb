# frozen_string_literal: true

module Admin
  module Settings
    # Per-BankConnection auto-sync settings (singular nested resource).
    # No `show` — schedule lives on the parent connection's show page.
    # No `destroy` — disabling is just enabled=false.
    class SyncSchedulesController < BaseController
      before_action :set_connection

      def edit
        @schedule = @connection.sync_schedule || @connection.build_sync_schedule
      end

      def update
        result = AutoSync::ScheduleUpserter.call(
          connection: @connection,
          user: current_user,
          input: AutoSync::ScheduleUpserter::Input.new(**schedule_params.to_h.symbolize_keys)
        )

        if result.success?
          redirect_to admin_transaction_syncs_path,
                      notice: "Auto-sync settings saved."
        else
          @schedule = result.schedule
          flash.now[:alert] = result.error.presence || "Could not save."
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_connection
        @connection = BankConnection.for_user(current_user).find(params[:bank_connection_id])
      end

      def schedule_params
        params.expect(sync_schedule: %i[enabled cadence preferred_hour])
      end
    end
  end
end
