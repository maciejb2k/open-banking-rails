# frozen_string_literal: true

# Devise session helpers shared by request and system specs. Request specs
# use Devise's IntegrationHelpers#sign_in (session stuffing for speed);
# system specs go through Warden::Test::Helpers#login_as which exercises
# the real cookie path.
module SignInHelpers
  def sign_in_as(user)
    Warden.test_mode!
    login_as(user, scope: :user)
  end

  def sign_in_request(user, password: "Password123!")
    post "/admin/sign_in", params: { user: { email: user.email, password: password } }
  end
end

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Warden::Test::Helpers, type: :system
  config.after(:each, type: :system) { Warden.test_reset! }
end
