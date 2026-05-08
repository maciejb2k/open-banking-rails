# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::ApplicationTool do
  it "inherits from MCP::Tool so subclassed tool definitions land in the gem's tool registry" do
    expect(described_class.ancestors).to include(::MCP::Tool)
  end

  it "extracts current_user from server_context via the helper" do
    user = create(:user)
    expect(described_class.current_user({ current_user: user })).to eq(user)
  end

  it "raises KeyError when server_context lacks :current_user (caller bug, not domain failure)" do
    expect { described_class.current_user({}) }.to raise_error(KeyError)
  end

  it "treats the :current_user key as a Symbol — a String key does not satisfy the contract" do
    user = create(:user)
    expect { described_class.current_user({ "current_user" => user }) }.to raise_error(KeyError)
  end

  it "wraps a string in a single-text MCP::Tool::Response via .text with error? false" do
    response = described_class.text("hello")

    expect(response).to be_a(::MCP::Tool::Response)
    expect(response.content.length).to eq(1)
    expect(response.content.first).to include(type: "text", text: "hello")
    expect(response.error?).to be(false)
  end

  it ".text coerces non-string inputs through to_s so callers don't have to pre-stringify" do
    response = described_class.text(42)

    expect(response.content.first[:text]).to eq("42")
  end

  it ".text accepts the empty string and produces a non-error response with one empty text part" do
    response = described_class.text("")

    expect(response.error?).to be(false)
    expect(response.content.first).to include(type: "text", text: "")
  end

  it "serializes a Hash payload to JSON in a single-text response via .json with error? false" do
    response = described_class.json(foo: 1, bar: %w[a b])

    parsed = JSON.parse(response.content.first[:text])
    expect(parsed).to eq("foo" => 1, "bar" => %w[a b])
    expect(response.error?).to be(false)
  end

  it ".json serializes top-level arrays of hashes (the typical list-tool response shape)" do
    response = described_class.json([ { id: 1, slug: "a" }, { id: 2, slug: "b" } ])

    parsed = JSON.parse(response.content.first[:text])
    expect(parsed).to eq([ { "id" => 1, "slug" => "a" }, { "id" => 2, "slug" => "b" } ])
  end

  it ".json round-trips nested data structures including booleans, nil, and integers" do
    payload = { items: [ { id: 1, active: true, deleted_at: nil } ], count: 1 }

    response = described_class.json(payload)
    parsed = JSON.parse(response.content.first[:text])

    expect(parsed).to eq("items" => [ { "id" => 1, "active" => true, "deleted_at" => nil } ], "count" => 1)
  end

  it "produces an error response prefixed with 'Error: ' via .error with error? true" do
    response = described_class.error("boom")

    expect(response.content.first[:text]).to eq("Error: boom")
    expect(response.error?).to be(true)
  end

  it ".error includes the message in the wire-format to_h envelope under isError: true" do
    envelope = described_class.error("boom").to_h

    expect(envelope[:isError]).to be(true)
    expect(envelope[:content].first[:text]).to eq("Error: boom")
  end

  it "from_result invokes on_success on success and forwards the result to the lambda" do
    success = Struct.new(:success?, :payload).new(true, "ok")

    captured = nil
    response = described_class.from_result(success, on_success: ->(r) { captured = r; described_class.text(r.payload) })

    expect(captured).to eq(success)
    expect(response.error?).to be(false)
    expect(response.content.first[:text]).to eq("ok")
  end

  it "from_result returns an error envelope built from result.error when the failed result responds to :error" do
    failure = Struct.new(:success?, :error).new(false, "domain message")

    response = described_class.from_result(failure, on_success: ->(_) { raise "should not run" })

    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to eq("Error: domain message")
  end

  it "from_result falls back to joining error_messages when the failed result has no :error reader" do
    failure_class = Class.new do
      def success?       = false
      def error_messages = [ "name can't be blank", "amount is invalid" ]
    end

    response = described_class.from_result(failure_class.new, on_success: ->(_) { raise "should not run" })

    expect(response.error?).to be(true)
    expect(response.content.first[:text]).to include("name can't be blank")
    expect(response.content.first[:text]).to include("amount is invalid")
  end

  it "from_result prefers result.error over result.error_messages when both are present" do
    failure = Struct.new(:success?, :error, :error_messages).new(false, "single line", [ "list", "messages" ])

    response = described_class.from_result(failure, on_success: ->(_) { raise "should not run" })

    expect(response.content.first[:text]).to eq("Error: single line")
    expect(response.content.first[:text]).not_to include("list")
  end

  it "from_result does not call on_success when the result is a failure" do
    failure = Struct.new(:success?, :error).new(false, "nope")
    invoked = false

    described_class.from_result(failure, on_success: ->(_) { invoked = true; described_class.text("won't run") })

    expect(invoked).to be(false)
  end
end
