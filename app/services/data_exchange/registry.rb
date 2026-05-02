# frozen_string_literal: true

module DataExchange
  # Resource registry. Lookup by key + topo sort by `depends_on` declarations
  # so export and import always walk the graph parents-first.
  #
  # Adding a resource = one line in RESOURCES + one new class file under
  # app/services/data_exchange/resources/. The mapping is name-based
  # (constantized lazily) so Zeitwerk reload in dev never serves a stale
  # class object — `constantize` always returns the freshly loaded one.
  module Registry
    DependencyError = Class.new(StandardError)

    # Topological order is computed from `depends_on` declarations on each
    # resource — the order here is just the canonical lookup table.
    RESOURCES = {
      tpp_credentials:  "DataExchange::Resources::TppCredentialResource",
      bank_connections: "DataExchange::Resources::BankConnectionResource",
      bank_accounts:    "DataExchange::Resources::BankAccountResource"
      # Add as you go:
      # categories:         "DataExchange::Resources::CategoryResource",
      # merchants:          "DataExchange::Resources::MerchantResource",
      # merchant_rules:     "DataExchange::Resources::MerchantRuleResource",
      # bank_transactions:  "DataExchange::Resources::BankTransactionResource",
      # manual_transactions:"DataExchange::Resources::ManualTransactionResource",
      # enrichments:        "DataExchange::Resources::EnrichmentResource",
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

      # Topologically ordered keys — parents before children. Use for both
      # export (so the bundle layout is dependency-stable for review) and
      # import (so RefMap is populated by the time a child needs to look up
      # a parent).
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
