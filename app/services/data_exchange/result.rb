# frozen_string_literal: true

module DataExchange
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
