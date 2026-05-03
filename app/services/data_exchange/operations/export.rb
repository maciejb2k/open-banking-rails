# frozen_string_literal: true

module DataExchange
  module Operations
    class Export < Base
      Failed = Class.new(StandardError)
      Result = Struct.new(:blob, :run, keyword_init: true)

      KIND = "data_export"

      def initialize(user:, resource_keys:, passphrase:)
        @user          = user
        @resource_keys = resource_keys.map(&:to_sym)
        @passphrase    = passphrase
      end

      def call
        validate_inputs!

        ordered  = Registry.ordered(@resource_keys)
        @run     = create_run(ordered)
        payload  = build_payload(ordered)
        manifest = build_manifest(ordered, payload)
        blob     = Bundle.dump(manifest: manifest, payload: payload, passphrase: @passphrase)

        @run.succeed!(summary: {
          "bundle_id"         => manifest["bundle_id"],
          "bytes"             => blob.bytesize,
          "counts"            => manifest["counts"],
          "resource_versions" => manifest["resource_versions"]
        })
        Result.new(blob: blob, run: @run)
      rescue StandardError => e
        @run&.fail!(error: e.message, summary: { "resource_keys" => @resource_keys.map(&:to_s) })
        raise
      end

      private

      def validate_inputs!
        raise Failed, "no resources selected" if @resource_keys.empty?
        raise Failed, "passphrase required"   if @passphrase.to_s.empty?
      end

      def create_run(ordered)
        OperationRun.create!(
          kind:              KIND,
          status:            "running",
          trigger:           "manual",
          started_at:        Time.current,
          triggered_by_user: @user,
          subject:           @user,
          params:            { "resource_keys" => ordered.map(&:to_s) },
          summary:           {}
        )
      end

      def build_payload(ordered_keys)
        ordered_keys.each_with_object({}) do |key, payload|
          resource = Registry.fetch(key).new(user: @user)
          payload[key.to_s] = serialize_records(resource)
        end
      end

      def serialize_records(resource)
        version = resource.class.resource_version

        resource.scope_for_export.find_each.map do |record|
          {
            "export_id"  => record.id,
            "_v"         => version,
            "attributes" => stringify(resource.serialize(record)),
            "references" => stringify_refs(resource.references(record))
          }
        end
      end

      def build_manifest(ordered_keys, payload)
        counts = ordered_keys.to_h { |k| [ k.to_s, payload[k.to_s].size ] }

        {
          "format_version"     => Bundle::FORMAT_VERSION,
          "bundle_id"          => SecureRandom.uuid,
          "exported_at"        => Time.current.iso8601,
          "source_env"         => Rails.env,
          "source_fingerprint" => source_fingerprint,
          "app_version"        => app_version,
          "exported_by"        => { "user_id" => @user.id, "email" => @user.email },
          "resource_versions"  => ordered_keys.to_h { |k| [ k.to_s, Registry.fetch(k).resource_version ] },
          "counts"             => counts
        }
      end

      # HMAC of AR encryption primary key - UX hint "from THIS instance" without
      # exposing the key. Never used for verification.
      def source_fingerprint
        primary = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].to_s
        return nil if primary.empty?

        OpenSSL::HMAC.hexdigest("SHA256", primary, "data-exchange-fingerprint-v1").first(16)
      end

      def app_version
        Rails.application.config.respond_to?(:app_version) ? Rails.application.config.app_version : nil
      end

      def stringify(hash)
        hash.transform_keys(&:to_s).transform_values { |v| serializable(v) }
      end

      def stringify_refs(refs)
        refs.transform_keys(&:to_s).transform_values { |(rk, sid)| [ rk.to_s, sid ] }
      end

      def serializable(value)
        case value
        when Time, DateTime then value.iso8601(6)
        when Date           then value.iso8601
        when BigDecimal     then value.to_s("F")
        else value
        end
      end
    end
  end
end
