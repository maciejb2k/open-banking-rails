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

  it "raises Failed without writing an OperationRun when the user has no configured LLM" do
    user = create(:user)

    expect { described_class.call(user: user) }.to raise_error(described_class::Failed, /not configured/)
    expect(OperationRun.where(kind: described_class::KIND, triggered_by_user: user).count).to eq(0)
  end
end
