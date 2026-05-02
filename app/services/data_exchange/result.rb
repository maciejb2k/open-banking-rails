# frozen_string_literal: true

module DataExchange
  # Outcome of an import (or a per-resource slice of one). Counts are flat
  # across resources; `per_resource` keeps the breakdown for the UI summary.
  # `run` is the OperationRun this import was tracked under — populated by
  # Operations::Import once the run is created, used by callers that want
  # to link to the audit row (`admin_versions` etc.).
  Result = Struct.new(
    :imported, :updated, :skipped, :failed, :warnings, :per_resource, :run,
    keyword_init: true
  ) do
    def self.empty
      new(imported: 0, updated: 0, skipped: 0, failed: 0, warnings: [], per_resource: {}, run: nil)
    end

    def record(resource_key, outcome)
      per_resource[resource_key] ||= { imported: 0, updated: 0, skipped: 0, failed: 0 }
      per_resource[resource_key][outcome] += 1
      send("#{outcome}=", send(outcome) + 1)
    end

    def warn(message)
      warnings << message
    end

    def total
      imported + updated + skipped + failed
    end
  end
end
