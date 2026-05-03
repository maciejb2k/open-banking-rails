# frozen_string_literal: true

module DataExchange
  module Resources
    # Subclasses declare `key`, `model`, `depends_on` and implement
    # `permitted_attributes`, `natural_key_attrs`, `scope_for_export`. The base
    # provides `apply!` which handles natural-key lookup, FK remapping,
    # conflict strategy, and version upgrade.
    class Base
      # Bump in a subclass and add `def upgrade(attrs, from:); ...; end` when
      # the serialized shape changes.
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

      def permitted_attributes
        raise NotImplementedError
      end

      # Default = everything. Override to freeze fields the destination
      # instance owns (status / synced_at / last_error …).
      def updatable_attributes
        permitted_attributes
      end

      def natural_key_attrs
        raise NotImplementedError
      end

      def scope_for_export
        raise NotImplementedError
      end

      # `encrypts` reader returns plaintext - bundle carries plaintext, gets
      # re-encrypted under destination keys on import.
      def serialize(record)
        permitted_attributes.each_with_object({}) { |attr, h| h[attr.to_s] = record.public_send(attr) }
      end

      # { fk_column => [resource_key, source_id] }. nil source_id = no reference.
      def references(_record)
        {}
      end

      # Override + bump RESOURCE_VERSION when the serialized shape changes.
      def upgrade(attrs, from:)
        attrs
      end

      # Hook for resources whose ownership isn't `user_id` (BankConnection
      # owns through TppCredential, Enrichment through its source transaction).
      def stamp_ownership!(attrs, _refs)
        attrs["user_id"] = user.id if self.class.model.column_names.include?("user_id")
      end

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

      # ALWAYS scoped to the owning user.
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
                "#{self.class.key} conflict on #{natural_key_attrs.inspect} - record already exists"
        else
          raise ArgumentError, "unknown conflict strategy: #{strategy.inspect}"
        end
      end

      # Required FK with missing parent → fail; optional FK with missing
      # parent → drop to nil. Required-ness is read from the column NULL
      # constraint.
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
