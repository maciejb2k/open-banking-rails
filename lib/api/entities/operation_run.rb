# frozen_string_literal: true

module Entities
  class OperationRun < Grape::Entity
    expose :id,            documentation: { type: Integer }
    expose :kind,          documentation: { type: String }
    expose :status,        documentation: { type: String, desc: "queued / running / succeeded / partial / failed" }
    expose :trigger,       documentation: { type: String, desc: "manual / scheduled" }
    expose :params,        documentation: { type: Hash, desc: "Run input parameters" }
    expose :summary,       documentation: { type: Hash, desc: "Result summary populated when finished" }
    expose :error,         documentation: { type: String }
    expose :scheduled_for, documentation: { type: String }
    expose :started_at,    documentation: { type: String }
    expose :finished_at,   documentation: { type: String }
    expose :subject_type,  documentation: { type: String }
    expose :subject_id,    documentation: { type: Integer }
    expose :created_at,    documentation: { type: String }
  end
end
