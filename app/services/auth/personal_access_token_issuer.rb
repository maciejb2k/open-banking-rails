# frozen_string_literal: true

module Auth
  class PersonalAccessTokenIssuer
    Input = Struct.new(:name, keyword_init: true) do
      def normalized_name
        name.to_s.strip
      end
    end

    Result = Struct.new(:success?, :token_record, :raw_token, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(user:, input:)
      @user  = user
      @input = input
    end

    def call
      raw    = "#{PersonalAccessToken::PREFIX}#{SecureRandom.urlsafe_base64(PersonalAccessToken::RAW_BYTES)}"
      digest = PersonalAccessToken.digest_for(raw)

      record = @user.personal_access_tokens.create!(
        name:         @input.normalized_name,
        token_digest: digest,
        last_four:    raw.last(4)
      )

      Result.new(success?: true, token_record: record, raw_token: raw)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, token_record: e.record, error_messages: e.record.errors.full_messages)
    end
  end
end
