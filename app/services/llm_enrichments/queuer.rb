# frozen_string_literal: true

module LlmEnrichments
  class Queuer
    KIND = "llm_enrichment"
    NotConfigured = Class.new(StandardError)

    Input = Struct.new(:limit, keyword_init: true) do
      def normalized_limit
        (limit.presence || ::Llm::EnrichmentRunner::DEFAULT_LIMIT).to_i
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
      unless @user.llm_setting&.configured?
        return Result.new(success?: false, error_messages: [ "Configure an LLM provider in Preferences before running enrichment." ])
      end

      run = ::OperationRun.create!(
        kind:              KIND,
        status:            "queued",
        trigger:           "manual",
        triggered_by_user: @user,
        subject:           @user,
        params:            { "limit" => @input.normalized_limit },
        summary:           {}
      )
      ::LlmEnrichmentJob.perform_later(run.id)
      Result.new(success?: true, run: run)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error_messages: e.record.errors.full_messages)
    end
  end
end
