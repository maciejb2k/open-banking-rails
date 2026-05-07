# frozen_string_literal: true

module Mcp
  class ServerBuilder
    def self.call(...) = new(...).call

    def initialize(user:)
      @user = user
    end

    def call
      ::MCP::Server.new(
        name:    "open-banking-rails",
        version: "1.0.0",
        tools:   tool_classes,
        server_context: { current_user: @user }
      )
    end

    private

    def tool_classes
      [
        ::Mcp::Tools::Cash::CreateTransaction,
        ::Mcp::Tools::Cash::UpdateTransaction,
        ::Mcp::Tools::Cash::DeleteTransaction,
        ::Mcp::Tools::Transactions::List,
        ::Mcp::Tools::Transactions::Get,
        ::Mcp::Tools::Transactions::Classify,
        ::Mcp::Tools::Categories::List,
        ::Mcp::Tools::Categories::Create,
        ::Mcp::Tools::Categories::Update,
        ::Mcp::Tools::Categories::Archive,
        ::Mcp::Tools::Categories::Unarchive,
        ::Mcp::Tools::Merchants::List,
        ::Mcp::Tools::Merchants::Create,
        ::Mcp::Tools::Merchants::Update,
        ::Mcp::Tools::Merchants::Archive,
        ::Mcp::Tools::Merchants::Unarchive,
        ::Mcp::Tools::Merchants::Approve,
        ::Mcp::Tools::BankAccounts::List,
        ::Mcp::Tools::BankAccounts::RefreshDetails,
        ::Mcp::Tools::BankAccounts::RefreshBalances,
        ::Mcp::Tools::BankConnections::List,
        ::Mcp::Tools::BankConnections::Refresh,
        ::Mcp::Tools::Analytics::CashFlow,
        ::Mcp::Tools::Analytics::Spend,
        ::Mcp::Tools::Analytics::TopMerchants,
        ::Mcp::Tools::Operations::QueueTransactionSync,
        ::Mcp::Tools::Operations::QueueLlmEnrichment
      ]
    end
  end
end
