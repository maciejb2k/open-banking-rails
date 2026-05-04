# frozen_string_literal: true

class Api < Grape::API
  prefix :api
  format :json
  version "v1", using: :path

  helpers ::Helpers::AuthHelper
  helpers ::Helpers::PagyHelper
  helpers ::Helpers::ErrorHelper

  rescue_from ActiveRecord::RecordNotFound do |e|
    error!({ message: e.message }, 404)
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    error!({ message: e.record.errors.full_messages.join(", "), details: e.record.errors.full_messages }, 422)
  end

  rescue_from ActiveRecord::StaleObjectError do
    error!({ message: "Resource was modified by another request, try again." }, 409)
  end

  rescue_from Grape::Exceptions::ValidationErrors do |e|
    error!({ message: "Invalid parameters.", details: e.full_messages }, 400)
  end

  rescue_from Grape::Exceptions::MethodNotAllowed do |e|
    error!(e.message, 405, e.headers)
  end

  rescue_from :all do |e|
    span = OpenTelemetry::Trace.current_span
    span.record_exception(e)
    span.status = OpenTelemetry::Trace::Status.error(e.message)

    Rails.logger.error("[API] #{e.class}: #{e.message}\n  #{e.backtrace.first(10).join("\n  ")}")
    body = Rails.env.test? || Rails.env.development? ? "#{e.class}: #{e.message}" : "Internal server error."
    error!({ message: body }, 500)
  end

  mount ::Resources::Transactions
  mount ::Resources::CashTransactions
  mount ::Resources::BankTransactions
  mount ::Resources::TransactionEnrichments
  mount ::Resources::Categories
  mount ::Resources::Merchants
  mount ::Resources::MerchantRules
  mount ::Resources::BankAccounts
  mount ::Resources::BankConnections
  mount ::Resources::TppCredentials
  mount ::Resources::TransactionSyncs
  mount ::Resources::LlmEnrichments
  mount ::Resources::Analytics::CashFlow
  mount ::Resources::Analytics::Spend
  mount ::Resources::Analytics::TopMerchants
  mount ::Resources::Analytics::Categories
  mount ::Resources::Analytics::Merchants

  add_swagger_documentation(
    mount_path: "/swagger_doc",
    base_path: "/",
    hide_documentation_path: true,
    hide_format: true,
    info: {
      title: "Open Banking Rails API",
      description: "Personal-finance JSON API. All endpoints require a Personal Access Token in the Authorization header.",
      version: "1.0.0"
    }
  )
end
