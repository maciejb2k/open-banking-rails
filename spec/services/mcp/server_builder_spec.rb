# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::ServerBuilder do
  it "builds an MCP::Server named open-banking-rails with the user injected into server_context" do
    user = create(:user)

    server = described_class.call(user: user)

    expect(server).to be_a(::MCP::Server)
    expect(server.name).to eq("open-banking-rails")
    expect(server.version).to eq("1.0.0")
    expect(server.server_context.fetch(:current_user)).to eq(user)
  end

  it "registers every Mcp::Tools::*::* class so MCP tools/list exposes the full surface" do
    user = create(:user)
    expected_tools = [
      Mcp::Tools::Cash::CreateTransaction, Mcp::Tools::Cash::UpdateTransaction, Mcp::Tools::Cash::DeleteTransaction,
      Mcp::Tools::Transactions::List, Mcp::Tools::Transactions::Get, Mcp::Tools::Transactions::Classify,
      Mcp::Tools::Categories::List, Mcp::Tools::Categories::Create, Mcp::Tools::Categories::Update,
      Mcp::Tools::Categories::Archive, Mcp::Tools::Categories::Unarchive,
      Mcp::Tools::Merchants::List, Mcp::Tools::Merchants::Create, Mcp::Tools::Merchants::Update,
      Mcp::Tools::Merchants::Archive, Mcp::Tools::Merchants::Unarchive, Mcp::Tools::Merchants::Approve,
      Mcp::Tools::BankAccounts::List, Mcp::Tools::BankAccounts::RefreshDetails, Mcp::Tools::BankAccounts::RefreshBalances,
      Mcp::Tools::BankConnections::List, Mcp::Tools::BankConnections::Refresh,
      Mcp::Tools::Analytics::CashFlow, Mcp::Tools::Analytics::Spend, Mcp::Tools::Analytics::TopMerchants,
      Mcp::Tools::Operations::QueueTransactionSync, Mcp::Tools::Operations::QueueLlmEnrichment
    ]

    server = described_class.call(user: user)

    expect(server.tools.values).to match_array(expected_tools)
  end

  it "all registered tools inherit from Mcp::ApplicationTool" do
    user = create(:user)
    server = described_class.call(user: user)

    server.tools.each_value do |tool_class|
      expect(tool_class.ancestors).to include(Mcp::ApplicationTool), "#{tool_class.name} should inherit Mcp::ApplicationTool"
    end
  end
end
