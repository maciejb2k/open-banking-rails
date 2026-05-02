# frozen_string_literal: true

module DataExchange
  # Translates `(resource_key, source_id)` → destination_id during import.
  # Populated as parents are written; consulted as children remap their FKs.
  # Lookup miss returns nil — caller decides whether that's fatal (required FK)
  # or just a soft drop (optional FK).
  class RefMap
    def initialize
      @map = Hash.new { |h, k| h[k] = {} }
    end

    def record(resource_key, source_id, destination_id)
      return if source_id.nil?

      @map[resource_key.to_sym][source_id.to_i] = destination_id
    end

    def lookup(resource_key, source_id)
      return nil if source_id.nil?

      @map[resource_key.to_sym][source_id.to_i]
    end

    def known?(resource_key, source_id)
      @map[resource_key.to_sym].key?(source_id.to_i)
    end
  end
end
