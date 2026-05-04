# frozen_string_literal: true

module TransactionSyncs
  class Queuer
    KIND = "transaction_sync"

    Input = Struct.new(:bank_connection_id, :date_from, :date_to, keyword_init: true) do
      def run_params
        { date_from: date_from.presence&.to_s, date_to: date_to.presence&.to_s }.compact
      end
    end

    Result = Struct.new(:success?, :run, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(user:, input:)
      @user  = user
      @input = input
    end

    def call
      run = ::OperationRun.create!(
        kind:              KIND,
        status:            "queued",
        trigger:           "manual",
        triggered_by_user: @user,
        subject:           resolve_subject,
        params:            @input.run_params,
        summary:           {}
      )
      ::TransactionSyncJob.perform_later(run.id)
      Result.new(success?: true, run: run)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error_messages: e.record.errors.full_messages)
    end

    private

    def resolve_subject
      return @user if @input.bank_connection_id.blank?
      ::BankConnection.for_user(@user).active.find_by(id: @input.bank_connection_id) || @user
    end
  end
end
