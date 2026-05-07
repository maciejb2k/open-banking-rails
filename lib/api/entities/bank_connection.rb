# frozen_string_literal: true

module Entities
  class BankConnection < Grape::Entity
    expose :id,                  documentation: { type: Integer }
    expose :bank_name,           documentation: { type: String }
    expose :bank_slug,           documentation: { type: String }
    expose :bank_country,        documentation: { type: String }
    expose :psu_type,            documentation: { type: String, desc: "personal / business" }
    expose :status,              documentation: { type: String }
    expose :authorized_at,       documentation: { type: String }
    expose :valid_until,         documentation: { type: String }
    expose :last_refreshed_at,   documentation: { type: String }
    expose :last_synced_at,      documentation: { type: String }
    expose :access_balances,     documentation: { type: "Boolean" }
    expose :access_transactions, documentation: { type: "Boolean" }
    expose :replaces_id,         documentation: { type: Integer }
    expose :tpp_credential_id,   documentation: { type: Integer }
    expose :last_error,          documentation: { type: String }
  end
end
