# frozen_string_literal: true

module EnableBanking
  # PSU-IP-Address / PSU-User-Agent are required by some banks (mBank).
  # Network/transport errors map to a failed Result with status 0; crypto/
  # config errors propagate as EnableBanking::ConfigError.
  class Client
    DEFAULT_BASE_URL = "https://api.enablebanking.com"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30

    def initialize(credential, base_url: DEFAULT_BASE_URL)
      @credential = credential
      @base_url = base_url
    end

    def get(path, params = {})
      request(:get, path, params: params)
    end

    def post(path, body)
      request(:post, path, body: body)
    end

    def delete(path)
      request(:delete, path)
    end

    private

    def request(method, path, params: nil, body: nil)
      response = connection.public_send(method) do |req|
        req.url(path)
        req.headers["Authorization"] = "Bearer #{jwt}"
        req.headers["PSU-IP-Address"] = ENV["PSU_IP_ADDRESS"] if ENV["PSU_IP_ADDRESS"].present?
        req.headers["PSU-User-Agent"] = ENV["PSU_USER_AGENT"] if ENV["PSU_USER_AGENT"].present?
        req.params.update(params) if params && !params.empty?
        req.body = body if body
      end

      Result.new(
        success: response.success?,
        status: response.status,
        data: response.body,
        headers: response.headers.to_h,
        error: response.success? ? nil : extract_error(response)
      )
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError => e
      Result.new(success: false, status: 0, data: nil, headers: {}, error: "#{e.class.name.demodulize}: #{e.message}")
    end

    def jwt
      JwtSigner.new(@credential).sign
    end

    def connection
      @connection ||= Faraday.new(url: @base_url) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = READ_TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    def extract_error(response)
      body = response.body
      if body.is_a?(Hash)
        parts = [ body["error"], body["message"], body["detail"] ].filter_map { |p| p.to_s.presence }
        return parts.join(" - ") if parts.any?
        body.to_json
      else
        body.to_s.presence || "HTTP #{response.status}"
      end
    end
  end
end
