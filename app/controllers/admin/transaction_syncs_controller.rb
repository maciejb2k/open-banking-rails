# frozen_string_literal: true

module Admin
  # Authorization: scoped to runs whose triggered_by_user_id = current_user.id.
  # Scheduled (cron) runs must also stamp triggered_by_user_id so they appear here.
  class TransactionSyncsController < BaseController
    KIND = "transaction_sync"

    def index
      scope = OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id)
      @pagy, @collection = paginated(scope, default_sort: "created_at desc", includes: :subject)

      @schedule_rows = current_user_connections.map { |c| [ c, c.sync_schedule ] }
    end

    def show
      @run = scoped_runs.includes(:subject).find(params[:id])
      @account_rows = Array(@run.summary["accounts"])
    end

    def new
      @user_bank_connections = current_user_connections
      @sync_default_from = Date.current - EnableBanking::BackfillWindow::DEFAULT_DAYS
      @sync_default_to = Date.current
    end

    def create
      result = TransactionSyncs::Queuer.call(
        user:  current_user,
        input: TransactionSyncs::Queuer::Input.new(
          bank_connection_id: params[:bank_connection_id],
          date_from:          params[:date_from],
          date_to:            params[:date_to]
        )
      )
      if result.success?
        redirect_to admin_transaction_sync_path(result.run), notice: "Sync ##{result.run.id} queued."
      else
        redirect_to new_admin_transaction_sync_path, alert: "Could not start sync: #{result.error}"
      end
    end

    private

    def scoped_runs
      OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id)
    end

    def current_user_connections
      BankConnection.for_user(current_user).active.includes(:sync_schedule).order(:bank_name)
    end
  end
end
