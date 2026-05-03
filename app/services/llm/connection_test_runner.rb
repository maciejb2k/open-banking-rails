# frozen_string_literal: true

module Llm
  # The probe embeds a fresh timestamp in the user prompt and demands the
  # model echo it in the schema - proves the response wasn't a cached canned
  # reply. A misbehaving provider that returns dummy JSON shows up as a
  # visible diff in the I/O panel on the run page.
  class ConnectionTestRunner
    Result = Struct.new(:run, :setting, keyword_init: true)
    Failed = Class.new(StandardError)

    KIND = "llm_connection_test"

    def self.call(...) = new(...).call

    def initialize(user:)
      @user = user
    end

    def call
      setting = @user.llm_setting
      raise Failed, "LLM provider is not configured" unless setting&.configured?

      run     = create_run(setting)
      request = build_request

      response = setting.build_client.structured(
        system_prompt: request["system_prompt"],
        user_prompt:   request["user_prompt"],
        schema:        request["schema"]
      )

      run.succeed!(summary: {
        "request"  => request.merge("provider" => setting.provider, "model" => setting.effective_model),
        "response" => response
      })
      setting.record_test_success!
      Result.new(run: run, setting: setting)
    rescue Llm::Client::Error => e
      run&.fail!(
        error:   e.message,
        summary: {
          "request"  => request&.merge("provider" => setting.provider, "model" => setting.effective_model),
          "response" => nil
        }
      )
      setting.record_test_failure!(e.message) if setting&.persisted?
      raise Failed, e.message
    end

    private

    def create_run(setting)
      OperationRun.create!(
        kind:              KIND,
        status:            "running",
        trigger:           "manual",
        started_at:        Time.current,
        triggered_by_user: @user,
        subject:           @user,
        params:            { "provider" => setting.provider, "model" => setting.effective_model },
        summary:           {}
      )
    end

    # String keys throughout - the request hash is persisted to summary (jsonb),
    # serialize → deserialize must round-trip.
    def build_request
      sent_at = Time.current.iso8601
      {
        "system_prompt" => "You are a connectivity probe. Reply with exactly the JSON " \
                           "{\"ok\": true, \"echo\": \"<the sent_at value from the user message>\"}.",
        "user_prompt"   => "ping sent_at=#{sent_at}",
        "schema"        => {
          type: "object", additionalProperties: false,
          required: %w[ok echo],
          properties: {
            ok:   { type: "boolean" },
            echo: { type: "string", description: "Echo of the sent_at timestamp from the user message." }
          }
        }
      }
    end
  end
end
