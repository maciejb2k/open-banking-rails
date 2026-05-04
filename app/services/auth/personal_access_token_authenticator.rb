# frozen_string_literal: true

module Auth
  # Single failure shape - callers must not branch on the reason
  # (avoids enumeration / timing leaks).
  class PersonalAccessTokenAuthenticator
    Result = Struct.new(:success?, :user, :token_record, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(raw_token:)
      @raw_token = raw_token
    end

    def call
      return failure unless @raw_token.is_a?(String) && @raw_token.start_with?(PersonalAccessToken::PREFIX)

      digest = PersonalAccessToken.digest_for(@raw_token)
      record = PersonalAccessToken.active.find_by(token_digest: digest)
      return failure unless record

      record.touch_used!
      Result.new(success?: true, user: record.user, token_record: record)
    end

    private

    def failure
      Result.new(success?: false)
    end
  end
end
