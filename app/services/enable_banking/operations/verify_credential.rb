# frozen_string_literal: true

module EnableBanking
  module Operations
    # Verifies a TppCredential against EB by hitting GET /application
    # and persisting the outcome on the credential record.
    #
    # Side effect — redirect_url reconciliation:
    #   - If EB has exactly ONE registered redirect_url and it differs
    #     from ours, we sync ours to match (no ambiguity).
    #   - If EB has MULTIPLE and ours isn't among them, we don't change
    #     anything — only flag a warning. The user must pick one in
    #     the EB console (or update ours manually).
    #
    # Returns a VerifyResult struct so the controller can render the
    # right flash without re-deriving anything. Never raises Failed —
    # API failures are reported via VerifyResult.failed(...).
    class VerifyCredential < Base
      VerifyResult = Struct.new(
        :status, :message, :redirect_url_synced_to, :registered_urls,
        keyword_init: true
      ) do
        def ok? = status == :ok
        def warning? = status == :warning
        def failed? = status == :failed
      end

      def initialize(credential)
        @credential = credential
      end

      def call
        result = Api::GetApplication.call(credential: @credential)

        if result.failure?
          @credential.update!(
            status: "error",
            last_verification_error: "HTTP #{result.status}: #{result.error}"
          )
          return VerifyResult.new(status: :failed, message: "Test failed: #{result.error_message}")
        end

        persist_success(result.data)
      rescue EnableBanking::Error => e
        @credential.update!(status: "error", last_verification_error: e.message)
        VerifyResult.new(status: :failed, message: "Configuration error: #{e.message}")
      end

      private

      def persist_success(data)
        registered = Array(data["redirect_urls"])
        sync_target = redirect_url_to_sync(registered)
        warning = redirect_url_warning(registered, sync_target)

        updates = {
          status: "active",
          last_verified_at: Time.current,
          last_verification_error: nil,
          metadata: data
        }
        updates[:redirect_url] = sync_target if sync_target

        @credential.update!(updates)

        VerifyResult.new(
          status: warning ? :warning : :ok,
          message: build_message(sync_target, warning),
          redirect_url_synced_to: sync_target,
          registered_urls: registered
        )
      end

      def redirect_url_to_sync(registered)
        return nil if registered.empty?
        return nil if registered.include?(@credential.redirect_url)
        registered.size == 1 ? registered.first : nil
      end

      def redirect_url_warning(registered, sync_target)
        return nil if sync_target
        return nil if registered.empty?
        return nil if registered.include?(@credential.redirect_url)
        "⚠ Local redirect_url (#{@credential.redirect_url}) is NOT in EB list. Choose one of: #{registered.join(', ')}"
      end

      def build_message(sync_target, warning)
        parts = [ "Connection verified — metadata refreshed." ]
        parts << "Local redirect_url updated to match EB: #{sync_target}" if sync_target
        parts << warning if warning
        parts.join(" ")
      end
    end
  end
end
