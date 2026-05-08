# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::ConnectionTestRunner do
  it "succeeds, persisting an OperationRun with provider/model params and the response in summary" do
    user = create(:user)
    setting = create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)

    result = described_class.call(user: user)

    expect(result.run).to be_persisted
    expect(result.run.kind).to eq(described_class::KIND)
    expect(result.run.status).to eq("succeeded")
    expect(result.run.params).to include("provider" => setting.provider, "model" => setting.effective_model)
    expect(result.run.summary["response"]).to be_a(Hash)
    expect(setting.reload.last_tested_at).to be_present
    expect(setting.last_test_error).to be_nil
  end

  it "returns the same setting on the Result that was tested" do
    user = create(:user)
    setting = create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)

    result = described_class.call(user: user)

    expect(result.setting.id).to eq(setting.id)
    expect(result.setting.provider).to eq(setting.provider)
  end

  it "stamps the run with trigger manual, subject and triggered_by_user pointing at the user, and kind llm_connection_test" do
    user = create(:user)
    create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)

    result = described_class.call(user: user)

    expect(result.run.trigger).to eq("manual")
    expect(result.run.triggered_by_user).to eq(user)
    expect(result.run.subject).to eq(user)
    expect(result.run.kind).to eq("llm_connection_test")
  end

  it "embeds a fresh sent_at timestamp in the user prompt and persists it in summary[request]" do
    user = create(:user)
    create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)

    travel_to(Time.utc(2026, 5, 8, 12, 34, 56)) do
      result = described_class.call(user: user)

      request = result.run.summary.fetch("request")
      expect(request["user_prompt"]).to match(/sent_at=2026-05-08T12:34:56Z/)
      expect(request["system_prompt"]).to include("connectivity probe")
    end

    expect(fake_llm.recorded_prompts.last[:user]).to match(/sent_at=2026-05-08T12:34:56Z/)
  end

  it "persists the request hash with string keys (JSONB round-trip safe)" do
    user = create(:user)
    create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)

    result = described_class.call(user: user)

    request = result.run.reload.summary.fetch("request")
    expect(request.keys).to include("system_prompt", "user_prompt", "schema", "provider", "model")
    expect(request.keys).to all(be_a(String))
  end

  it "drives a schema that requires both ok and echo so a misbehaving provider would fail validation" do
    user = create(:user)
    create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)

    described_class.call(user: user)

    schema = fake_llm.recorded_prompts.last[:schema]
    expect(schema).to include(type: "object")
    expect(Array(schema[:required])).to contain_exactly("ok", "echo")
    expect(schema.dig(:properties, :ok)).to include(type: "boolean")
    expect(schema.dig(:properties, :echo)).to include(type: "string")
  end

  it "calls structured exactly once per invocation (no retry, no fan-out)" do
    user = create(:user)
    create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)

    described_class.call(user: user)

    expect(fake_llm.recorded_prompts.size).to eq(1)
  end

  it "captures the model that was actually sent — provider default fills in for blank LlmSetting#model" do
    user = create(:user)
    setting = create(:llm_setting, user: user, model: nil)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)

    result = described_class.call(user: user)

    expect(setting.effective_model).not_to be_blank
    expect(result.run.params["model"]).to eq(setting.effective_model)
    expect(result.run.summary["request"]["model"]).to eq(setting.effective_model)
  end

  it "raises Failed and finalizes the run as failed when the LLM client raises Llm::Client::Error" do
    user = create(:user)
    setting = create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)
    fake_llm.set_failure(message: "rate limit exceeded")

    expect { described_class.call(user: user) }.to raise_error(described_class::Failed, /rate limit exceeded/)

    run = OperationRun.where(kind: described_class::KIND).last
    expect(run.status).to eq("failed")
    expect(run.error).to match(/rate limit/)
    expect(setting.reload.last_test_error).to match(/rate limit/)
  end

  it "stores the request payload in the failed run's summary so the I/O panel can render it" do
    user = create(:user)
    create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)
    fake_llm.set_failure(message: "boom")

    expect { described_class.call(user: user) }.to raise_error(described_class::Failed)

    run = OperationRun.where(kind: described_class::KIND).last
    expect(run.summary.fetch("request")).to include("system_prompt", "user_prompt", "schema", "provider", "model")
    expect(run.summary.fetch("response")).to be_nil
  end

  it "stamps last_tested_at on both success and failure so the UI can show 'last attempted'" do
    user = create(:user)
    setting = create(:llm_setting, user: user)
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)
    fake_llm.set_failure(message: "transient")

    expect { described_class.call(user: user) }.to raise_error(described_class::Failed)
    expect(setting.reload.last_tested_at).to be_present
  end

  it "raises Failed without writing an OperationRun when the user has no LlmSetting at all" do
    user = create(:user)

    expect { described_class.call(user: user) }.to raise_error(described_class::Failed, /not configured/)
    expect(OperationRun.where(kind: described_class::KIND, triggered_by_user: user).count).to eq(0)
  end

  it "raises Failed without writing an OperationRun when the LlmSetting exists but its api_key is blank (configured? is false)" do
    user = create(:user)
    create(:llm_setting, :invalid, user: user)

    expect { described_class.call(user: user) }.to raise_error(described_class::Failed, /not configured/)
    expect(OperationRun.where(kind: described_class::KIND, triggered_by_user: user).count).to eq(0)
  end

  it "does not leak the api_key into the OperationRun's params or summary on success or failure" do
    user = create(:user)
    setting = create(:llm_setting, user: user, api_key: "super-secret-token-9876")
    allow_any_instance_of(LlmSetting).to receive(:build_client).and_return(fake_llm)

    result = described_class.call(user: user)
    expect(result.run.attributes.values.compact.map(&:to_s).join("\n")).not_to include(setting.api_key)
    expect(result.run.params.to_json).not_to include(setting.api_key)
    expect(result.run.summary.to_json).not_to include(setting.api_key)

    fake_llm.set_failure(message: setting.api_key + "-leaked")
    expect { described_class.call(user: user) }.to raise_error(described_class::Failed)
    failed = OperationRun.where(kind: described_class::KIND, status: "failed").last
    expect(failed.params.to_json).not_to include("super-secret-token-9876")
  end
end
