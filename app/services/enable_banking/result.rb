# frozen_string_literal: true

module EnableBanking
  # Carries the outcome of a single API call. Queries return this object
  # rather than raising on non-2xx, so callers (controllers/services) can
  # decide how to react.
  Result = Struct.new(:success, :status, :data, :headers, :error, keyword_init: true) do
    def success?
      success
    end

    def failure?
      !success
    end

    def to_h
      { success: success, status: status, error: error }
    end
  end
end
