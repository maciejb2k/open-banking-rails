# frozen_string_literal: true

module Admin
  # Dedicated UI for transaction-sync OperationRuns. Other kinds (when added)
  # get their own controllers + views — the underlying OperationRun model is
  # shared, but each surface is concern-specific.
  #
  # Authorization: scoped to runs whose triggered_by_user_id = current_user.id.
  # Scheduled runs (cron) must also stamp triggered_by_user_id so they appear here.
  class TransactionSyncsController < BaseController
    KIND = "transaction_sync"

    def index
      scope = OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id)
      @pagy, @collection = paginated(scope, default_sort: "created_at desc", includes: :subject)
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
      run = OperationRun.create(
        kind: KIND,
        status: "queued",
        trigger: "manual",
        triggered_by_user: current_user,
        subject: resolve_subject,
        params: { date_from: params[:date_from].presence, date_to: params[:date_to].presence }.compact
      )

      if run.persisted?
        TransactionSyncJob.perform_later(run.id)
        redirect_to admin_transaction_sync_path(run), notice: "Sync ##{run.id} queued."
      else
        redirect_to new_admin_transaction_sync_path, alert: "Could not start sync: #{run.errors.full_messages.to_sentence}"
      end
    end

    private

    def scoped_runs
      OperationRun.where(kind: KIND, triggered_by_user_id: current_user.id)
    end

    # User picked a specific connection or "all" (= current_user).
    def resolve_subject
      connection_id = params[:bank_connection_id]
      if connection_id.present? && (connection = current_user_connections.find_by(id: connection_id))
        connection
      else
        current_user
      end
    end

    def current_user_connections
      BankConnection.for_user(current_user).active.order(:bank_name)
    end
  end
end
