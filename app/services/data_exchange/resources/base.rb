# frozen_string_literal: true

module DataExchange
  module Resources
    # Abstract per-model serializer/deserializer for the data-exchange bundle.
    #
    # One subclass per exportable resource. Subclasses declare:
    #
    #   key            — symbolic id used in the bundle and dependency graph
    #   model          — the AR class
    #   depends_on     — other resource keys this one references via FKs
    #
    # And implement:
    #
    #   permitted_attributes — allowlist of bundle fields → AR attrs
    #   natural_key_attrs    — columns that uniquely identify the record
    #                          inside the owning user's scope
    #   serialize(record)    — extra/custom shape if needed (default = read
    #                          permitted_attributes off the record, including
    #                          decrypted ciphertext via the `encrypts` reader)
    #   references(record)   — { fk_column => [resource_key, source_id] }
    #                          for FK remapping at import time
    #   scope_for_export(user) — AR relation, MUST be scoped to user
    #
    # The base provides a generic `apply!` that handles natural-key lookup,
    # FK remapping, conflict strategy, and version upgrade. Subclasses only
    # override what's actually different.
    class Base
      # Bump in a subclass and add `def upgrade(attrs, from:); ...; end` when
      # the serialized shape of that resource changes (rename, retype, split).
      RESOURCE_VERSION = 1

      class << self
        def key(value = nil)
          @key = value if value
          @key
        end

        def model(value = nil)
          @model = value if value
          @model
        end

        def depends_on(*keys)
          @dependencies = ((@dependencies || []) + keys).uniq
        end

        def dependencies
          @dependencies || []
        end

        def resource_version
          self::RESOURCE_VERSION
        end
      end

      attr_reader :user

      def initialize(user:)
        @user = user
      end

      # ── Subclass interface ────────────────────────────────────────────

      def permitted_attributes
        raise NotImplementedError
      end

      # Subset of permitted_attributes that may be overwritten on conflict.
      # Default = everything. Override to freeze e.g. status / synced_at /
      # last_error fields that the destination instance owns.
      def updatable_attributes
        permitted_attributes
      end

      def natural_key_attrs
        raise NotImplementedError
      end

      def scope_for_export
        raise NotImplementedError
      end

      # Default serialization reads permitted_attributes off the record. The
      # `encrypts` reader returns plaintext, which is what we want — bundle
      # carries plaintext, gets re-encrypted under destination keys on import.
      def serialize(record)
        permitted_attributes.each_with_object({}) { |attr, h| h[attr.to_s] = record.public_send(attr) }
      end

      # { fk_column => [resource_key, source_id] }. nil source_id is allowed
      # and treated as "no reference".
      def references(_record)
        {}
      end

      # Schema upgrade. No-op by default. Override + bump RESOURCE_VERSION
      # when the serialized shape changes.
      def upgrade(attrs, from:)
        attrs
      end

      # Hook for resources whose ownership isn't `user_id` (e.g. BankConnection
      # owns through TppCredential, Enrichment through its source transaction).
      # Default: stamp `user_id` from current user.
      def stamp_ownership!(attrs, _refs)
        attrs["user_id"] = user.id if self.class.model.column_names.include?("user_id")
      end

      # ── Apply one record from a bundle ────────────────────────────────

      # Returns one of :imported, :updated, :skipped. Raises on hard failure.
      def apply!(serialized:, ref_map:, strategy:)
        export_id = serialized.fetch("export_id")
        from_v    = serialized.fetch("_v", 1)
        raw_attrs = serialized.fetch("attributes", {})
        refs      = serialized.fetch("references", {})

        attrs = raw_attrs.slice(*permitted_attributes.map(&:to_s))
        attrs = upgrade(attrs, from: from_v) if from_v != self.class.resource_version

        remap_foreign_keys!(attrs, refs, ref_map)
        stamp_ownership!(attrs, refs)

        existing = find_existing(attrs)
        if existing
          outcome = handle_conflict!(existing, attrs, strategy)
          ref_map.record(self.class.key, export_id, existing.id)
          return outcome
        end

        record = build_new(attrs)
        record.save!
        ref_map.record(self.class.key, export_id, record.id)
        :imported
      end

      # Natural-key lookup ALWAYS scoped to the owning user. Subclasses can
      # override for non-trivial lookups (e.g. composite keys via joins).
      def find_existing(attrs)
        scope_for_export.find_by(natural_key_attrs.index_with { |attr| attrs[attr.to_s] })
      end

      private

      def build_new(attrs)
        self.class.model.new(attrs)
      end

      def handle_conflict!(existing, attrs, strategy)
        case strategy
        when :skip_existing then :skipped
        when :overwrite_existing
          existing.update!(attrs.slice(*updatable_attributes.map(&:to_s)))
          :updated
        when :fail_on_conflict
          raise Operations::Base::Failed,
                "#{self.class.key} conflict on #{natural_key_attrs.inspect} — record already exists"
        else
          raise ArgumentError, "unknown conflict strategy: #{strategy.inspect}"
        end
      end

      # Walk references hash, replace each `fk_column` with destination id from
      # RefMap. Required FK with missing parent ⇒ fail loudly. Optional FK with
      # missing parent ⇒ drop to nil and continue (caller resource decides which
      # is which by which columns it lists in `references`).
      def remap_foreign_keys!(attrs, refs, ref_map)
        refs.each do |fk_column, (resource_key, source_id)|
          next if source_id.nil?

          dest_id = ref_map.lookup(resource_key, source_id)
          if dest_id.nil?
            if required_fk?(fk_column)
              raise Operations::Base::Failed,
                    "#{self.class.key}: required reference #{resource_key}##{source_id} " \
                    "for column #{fk_column} not resolved (parent not in bundle and not on destination)"
            end
            attrs[fk_column.to_s] = nil
          else
            attrs[fk_column.to_s] = dest_id
          end
        end
      end

      def required_fk?(column)
        col = self.class.model.columns_hash[column.to_s]
        col && !col.null
      end
    end
  end
end
