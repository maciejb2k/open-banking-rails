# frozen_string_literal: true

module EnableBanking
  # Raised by JwtSigner / Client setup, not by HTTP responses.
  # HTTP non-2xx is reported via Result, not exceptions.
  class Error < StandardError; end
  class ConfigError < Error; end
end
