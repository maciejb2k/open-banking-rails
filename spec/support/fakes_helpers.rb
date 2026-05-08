# frozen_string_literal: true

require "concurrent/atomic/atomic_reference"

# Per-example holder for the in-memory fake adapters. The fakes live in
# `spec/support/fakes/`. Replacing the production EnableBanking::Client and
# Llm::Client.for entry points happens here so individual specs only need to
# reach for `fake_eb` / `fake_llm`.

module FakesHelpers
  CURRENT_EB  = Concurrent::AtomicReference.new(nil)
  CURRENT_LLM = Concurrent::AtomicReference.new(nil)

  def fake_eb
    CURRENT_EB.value
  end

  def fake_llm
    CURRENT_LLM.value
  end
end

RSpec.configure do |config|
  config.before(:each) do
    eb_fake  = Fakes::EnableBankingClient.new
    llm_fake = Fakes::LlmClient.new

    FakesHelpers::CURRENT_EB.value  = eb_fake
    FakesHelpers::CURRENT_LLM.value = llm_fake

    allow(EnableBanking::Client).to receive(:new) { eb_fake }
    allow(Llm::Client).to receive(:for) { llm_fake }
  end

  config.after(:each) do
    FakesHelpers::CURRENT_EB.value  = nil
    FakesHelpers::CURRENT_LLM.value = nil
  end
end
