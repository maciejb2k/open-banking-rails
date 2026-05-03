# frozen_string_literal: true

module EnableBanking
  Result = Struct.new(:success, :status, :data, :headers, :error, keyword_init: true) do
    def success?
      success
    end

    def failure?
      !success
    end

    def error_message
      error.presence || "HTTP #{status}"
    end

    def to_h
      { success: success, status: status, error: error }
    end
  end
end
