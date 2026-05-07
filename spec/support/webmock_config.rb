# frozen_string_literal: true

# Default policy is set in rails_helper.rb (disable_net_connect, allow
# localhost). This file provides URL matchers for the small number of
# real-adapter wire-format tests that bypass the in-memory fakes.
module WebMockHelpers
  def eb_url(path = nil)
    base = ::EnableBanking::Client::DEFAULT_BASE_URL
    path ? %r{\A#{Regexp.escape(base)}#{path}} : %r{\A#{Regexp.escape(base)}}
  end

  def gemini_url(model: nil)
    pattern = "generativelanguage.googleapis.com"
    pattern += "/.*#{Regexp.escape(model)}" if model
    Regexp.new(pattern)
  end

  def openai_url(endpoint: nil)
    pattern = "api.openai.com"
    pattern += "/#{Regexp.escape(endpoint.to_s)}" if endpoint
    Regexp.new(pattern)
  end
end

RSpec.configure do |config|
  config.include WebMockHelpers
end
