# frozen_string_literal: true

require "rails_helper"
require "ruby_llm"

RSpec.describe Llm::Clients::OpenAI do
  it "retries up to MAX_RETRIES on RubyLLM::RateLimitError, parsing the wait from common provider message formats" do
    client = described_class.new(api_key: "sk-test", model: "gpt-4")
    chat = double("chat")
    allow(chat).to receive(:with_instructions).and_return(chat)
    allow(chat).to receive(:with_schema).and_return(chat)
    responses = [
      -> { raise RubyLLM::RateLimitError.new("rate limited - retry after 7s") },
      -> { raise RubyLLM::RateLimitError.new("please try again in 0.5s") },
      -> { raise RubyLLM::RateLimitError.new("no hint about wait time") },
      -> { double("message", content: { "category" => "card" }) }
    ]
    allow(chat).to receive(:ask) { responses.shift.call }

    context = double("ctx")
    allow(context).to receive(:chat).and_return(chat)
    allow(client).to receive(:ruby_llm_context).and_return(context)

    waits = []
    allow(client).to receive(:sleep) { |t| waits << t }

    result = client.structured(system_prompt: "S", user_prompt: "U", schema: { type: "object" })

    expect(result).to eq({ "category" => "card" })
    expect(waits.size).to eq(3)
    expect(waits[0]).to eq(8.0)
    expect(waits[1]).to eq(1.5)
    expect(waits[2]).to eq(30.0)
  end

  it "raises Llm::Client::Error wrapping the upstream class once MAX_RETRIES is exceeded" do
    client = described_class.new(api_key: "sk-test", model: "gpt-4")
    chat = double("chat")
    allow(chat).to receive(:with_instructions).and_return(chat)
    allow(chat).to receive(:with_schema).and_return(chat)
    allow(chat).to receive(:ask).and_raise(RubyLLM::RateLimitError.new("always rate limited"))

    context = double("ctx")
    allow(context).to receive(:chat).and_return(chat)
    allow(client).to receive(:ruby_llm_context).and_return(context)
    allow(client).to receive(:sleep)

    expect {
      client.structured(system_prompt: "S", user_prompt: "U", schema: { type: "object" })
    }.to raise_error(Llm::Client::Error, /OpenAI API error.*RateLimitError/)
  end
end
