# frozen_string_literal: true

module Entities
  class TppCredential < Grape::Entity
    expose :id,                 documentation: { type: Integer }
    expose :name,               documentation: { type: String }
    expose :provider,           documentation: { type: String }
    expose :environment,        documentation: { type: String }
    expose :status,             documentation: { type: String }
    expose :primary,            documentation: { type: "Boolean" }
    expose :redirect_url,       documentation: { type: String }
    expose :cert_expires_at,    documentation: { type: String }
    expose :last_verified_at,   documentation: { type: String }
    expose :last_verification_error, documentation: { type: String }
  end
end
