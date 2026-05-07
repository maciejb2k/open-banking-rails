# frozen_string_literal: true

module DataExchange
  module Operations
    # OperationRun is created `running` AFTER the bundle parses cleanly so
    # wrong-passphrase typos don't pollute audit history.
    #
    # Multi-tenant guard: user_id is ALWAYS taken from `user`, never from
    # bundle data - enforced in Resources::Base#stamp_ownership! and the
    # per-resource permitted_attributes allowlist.
    class Import < Base
      Failed = Class.new(StandardError)

      KIND = "data_import"

      STRATEGIES = %i[skip_existing overwrite_existing fail_on_conflict].freeze

      MAX_BUNDLE_BYTES = 10 * 1024 * 1024  # post-decrypt cap; bundle stays in memory
      MAX_RECORDS      = 50_000

      def initialize(user:, bundle_blob:, passphrase:, strategy: :skip_existing)
        @user        = user
        @bundle_blob = bundle_blob
        @passphrase  = passphrase
        @strategy    = strategy.to_sym
      end

      def call
        validate_inputs!
        bundle = parse_bundle!
        validate_bundle!(bundle)

        @run = create_run(bundle)
        result = apply!(bundle)

        @run.succeed!(summary: run_summary(result, bundle))
        result.run = @run
        result
      rescue StandardError => e
        @run&.fail!(error: e.message, summary: run_summary(@partial_result, @parsed_bundle))
        raise
      end

      private

      def validate_inputs!
        raise Failed, "passphrase required" if @passphrase.to_s.empty?
        raise Failed, "unknown strategy: #{@strategy}" unless STRATEGIES.include?(@strategy)
        raise Failed, "AR encryption keys not configured on this instance - cannot store sensitive fields" \
          unless ar_encryption_configured?
        raise Failed, "bundle is empty" if @bundle_blob.to_s.empty?
        # *2: cap is on decrypted size; encrypted is roughly the same plus
        # envelope + IV + tag overhead.
        raise Failed, "bundle exceeds size limit" if @bundle_blob.bytesize > MAX_BUNDLE_BYTES * 2
      end

      def parse_bundle!
        @parsed_bundle = Bundle.load(@bundle_blob, passphrase: @passphrase)
      rescue BundleCipher::InvalidPassphrase => e
        raise Failed, e.message
      rescue BundleCipher::MalformedBundle, Bundle::InvalidFormat => e
        raise Failed, "bundle malformed: #{e.message}"
      end

      def validate_bundle!(bundle)
        total = bundle.resource_keys.sum { |k| bundle.records_for(k).size }
        raise Failed, "bundle has #{total} records (limit #{MAX_RECORDS})" if total > MAX_RECORDS

        unknown = bundle.resource_keys - Registry.all_keys
        raise Failed, "bundle references unknown resources: #{unknown.inspect}" if unknown.any?

        bundle.resource_keys.each do |key|
          klass = Registry.fetch(key)
          bundle_v   = bundle.manifest.dig("resource_versions", key.to_s) || 1
          known_v    = klass.resource_version
          next if bundle_v <= known_v

          raise Failed,
                "bundle resource #{key} version #{bundle_v} is newer than this build (#{known_v}) - upgrade target instance"
        end
      end

      def create_run(bundle)
        OperationRun.create!(
          kind:              KIND,
          status:            "running",
          trigger:           "manual",
          started_at:        Time.current,
          triggered_by_user: @user,
          subject:           @user,
          params: {
            "strategy"           => @strategy.to_s,
            "bundle_id"          => bundle.manifest["bundle_id"],
            "source_env"         => bundle.manifest["source_env"],
            "source_fingerprint" => bundle.manifest["source_fingerprint"],
            "exported_at"        => bundle.manifest["exported_at"]
          },
          summary: {}
        )
      end

      def apply!(bundle)
        @partial_result = Result.empty
        ref_map         = RefMap.new
        ordered         = Registry.ordered(bundle.resource_keys)

        ApplicationRecord.transaction do
          ordered.each do |key|
            resource = Registry.fetch(key).new(user: @user)
            bundle.records_for(key).each do |serialized|
              outcome = resource.apply!(serialized: serialized, ref_map: ref_map, strategy: @strategy)
              @partial_result.record(key, outcome)
            rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
              # Bubble up so the surrounding transaction rolls back - user
              # sees a clean "nothing imported" with the offending message.
              raise Failed, "#{key}: #{e.message}"
            end
          end
        end

        @partial_result
      end

      def run_summary(result, bundle)
        {
          "strategy" => @strategy.to_s,
          "bundle"   => bundle && {
            "id"          => bundle.manifest["bundle_id"],
            "source_env"  => bundle.manifest["source_env"],
            "exported_at" => bundle.manifest["exported_at"],
            "counts"      => bundle.manifest["counts"]
          },
          "result" => result && {
            "imported"     => result.imported,
            "updated"      => result.updated,
            "skipped"      => result.skipped,
            "failed"       => result.failed,
            "warnings"     => result.warnings,
            "per_resource" => result.per_resource
          }
        }.compact
      end

      def ar_encryption_configured?
        ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].to_s.length.positive?
      end
    end
  end
end
