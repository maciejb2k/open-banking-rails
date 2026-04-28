# frozen_string_literal: true

module EnableBanking
  # Carries the outcome of a single API call. Api wrappers return this object
  # rather than raising on non-2xx, so callers (controllers/operations) can
  # decide how to react.
  Result = Struct.new(:success, :status, :data, :headers, :error, keyword_init: true) do
    def success?
      success
    end

    def failure?
      !success
    end

    # Compact human-readable error suitable for flash messages.
    # Falls back to "HTTP <status>" when the API didn't include an error body.
    def error_message
      error.presence || "HTTP #{status}"
    end

    def to_h
      { success: success, status: status, error: error }
    end
  end
end
