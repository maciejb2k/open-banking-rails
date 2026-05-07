# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::ApplicationTool do
  it "extracts current_user from server_context via the helper" do
    user = create(:user)
    expect(described_class.current_user({ current_user: user })).to eq(user)
  end

  it "raises KeyError when server_context lacks :current_user (caller bug, not domain failure)" do
    expect { described_class.current_user({}) }.to raise_error(KeyError)
  end

  it "wraps a string in a single-text MCP::Tool::Response via .text" do
    response = described_class.text("hello")

    expect(response.content.length).to eq(1)
    expect(response.content.first).to include(type: "text", text: "hello")
  end

  it "serializes a Hash payload to JSON in a single-text response via .json" do
    response = described_class.json(foo: 1, bar: %w[a b])

    parsed = JSON.parse(response.content.first[:text])
    expect(parsed).to eq("foo" => 1, "bar" => %w[a b])
  end

  it "produces an error response prefixed with 'Error: ' via .error" do
    response = described_class.error("boom")

    expect(response.content.first[:text]).to eq("Error: boom")
    expect(response.error?).to be(true)
  end

  it "from_result branches on success: invokes on_success on success and returns error envelope on failure" do
    success = Struct.new(:success?, :payload).new(true, "ok")
    failure = Struct.new(:success?, :error_messages).new(false, [ "bad", "thing" ])

    success_response = described_class.from_result(success, on_success: ->(r) { described_class.text(r.payload) })
    failure_response = described_class.from_result(failure, on_success: ->(_) { raise "should not run" })

    expect(success_response.content.first[:text]).to eq("ok")
    expect(failure_response.error?).to be(true)
    expect(failure_response.content.first[:text]).to include("bad").and include("thing")
    expect(failure_response.content.first[:text]).to start_with("Error: ")
  end
end
