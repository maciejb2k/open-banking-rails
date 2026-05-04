# frozen_string_literal: true

class McpController < ActionController::API
  before_action :authenticate_with_pat!

  def handle
    server    = ::Mcp::ServerBuilder.call(user: @current_user)
    transport = ::MCP::Server::Transports::StreamableHTTPTransport.new(
      server, stateless: true, enable_json_response: true
    )
    status_code, headers, body = transport.handle_request(request)
    headers.each { |k, v| response.set_header(k, v) }
    self.response_body = body
    self.status = status_code
  end

  private

  def authenticate_with_pat!
    header = request.headers["Authorization"].to_s
    raw    = header.sub(/\Abearer\s+/i, "").presence
    result = ::Auth::PersonalAccessTokenAuthenticator.call(raw_token: raw)
    return render(json: { error: "Invalid or missing access token." }, status: :unauthorized) unless result.success?

    @current_user = result.user
  end
end
