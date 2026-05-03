# frozen_string_literal: true

module DataExchange
  # Mapping is name-based (constantized lazily) so Zeitwerk reload never serves
  # a stale class object.
  module Registry
    DependencyError = Class.new(StandardError)

    RESOURCES = {
      tpp_credentials:  "DataExchange::Resources::TppCredentialResource",
      bank_connections: "DataExchange::Resources::BankConnectionResource",
      bank_accounts:    "DataExchange::Resources::BankAccountResource"
    }.freeze

    class << self
      def fetch(key)
        name = RESOURCES.fetch(key.to_sym) do
          raise ArgumentError, "unknown resource: #{key.inspect}"
        end
        name.constantize
      end

      def all_keys
        RESOURCES.keys
      end

      # Parents before children - for both export (dependency-stable layout)
      # and import (RefMap populated by the time a child needs the parent).
      def ordered(keys)
        requested = keys.map(&:to_sym).uniq
        unknown = requested - all_keys
        raise ArgumentError, "unknown resources: #{unknown.inspect}" if unknown.any?

        sorted = []
        visiting = Set.new
        visited = Set.new

        visit = lambda do |key|
          return if visited.include?(key)
          raise DependencyError, "cycle detected at #{key}" if visiting.include?(key)

          visiting << key
          fetch(key).dependencies.each do |dep|
            next unless requested.include?(dep)

            visit.call(dep)
          end
          visiting.delete(key)
          visited << key
          sorted << key
        end

        requested.each(&visit)
        sorted
      end
    end
  end
end
