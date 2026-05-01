# frozen_string_literal: true

module Llm
  # End-to-end probe of the user's configured LLM provider:
  #
  #   1. Create an OperationRun (kind: "llm_connection_test", status: running)
  #   2. Build a tiny structured-output request that embeds the current
  #      timestamp in the user prompt and demands the model echo it back
  #      in the schema. The echo proves the response wasn't a cached
  #      canned reply — a misbehaving provider that returns dummy JSON
  #      gets caught by visual diff in the I/O panel on the run page.
  #   3. Call the provider via Llm::Client#structured.
  #   4. On success: mark the run succeeded, stamp last_tested_at on the
  #      LlmSetting, return Result(run:, setting:).
  #   5. On Llm::Client::Error: mark the run failed (with the request
  #      payload preserved in summary), record the test failure on the
  #      setting, and raise Failed with the provider's message. The
  #      OperationRun is still persisted in `failed` state so the user
  #      can see what went wrong in the run history.
  #
  # The pre-flight "is configured?" check stays in the caller — that's a
  # UX guard, not a probe outcome (a not-configured user should land in
  # the settings form, not in the run history).
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

    # String keys throughout — the request hash gets persisted into
    # OperationRun#summary (jsonb), and we want the round-trip from
    # serialize → deserialize to be a no-op.
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
