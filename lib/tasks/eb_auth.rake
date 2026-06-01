# frozen_string_literal: true

# Two-step EnableBanking auth via rake - backup path for when the admin UI
# OAuth flow is unusable (e.g. registered redirect_url at EnableBanking
# differs from the URL configured on the TppCredential).
#
# Step 1: kick off the auth, copy the printed URL into a browser, log in.
#   bin/rails banking:start_auth USER_EMAIL=you@example.com ASPSP=Revolut
#
# Step 2: bank redirects to credential.redirect_url with ?code=...&state=...
# Browser will likely show a connection error - that's fine, copy the params
# out of the URL bar and run:
#   bin/rails banking:finish_auth CODE=... STATE=...
#
# Env vars accepted by start_auth:
#   USER_EMAIL=     (required) email of the User that owns the TppCredential
#   ASPSP=          (required) bank name as EnableBanking expects it (e.g. Revolut, mBank)
#   COUNTRY=PL      ASPSP country (default: PL)
#   PSU_TYPE=       personal|business (default: personal)
#   DAYS=180        consent validity in days (1..180)
#   REDIRECT_URL=   one-shot override of credential.redirect_url for this /auth
#                   call. Not persisted. Use when the EnableBanking app is
#                   registered with a different callback than what's on the
#                   credential right now.
#   CREDENTIAL_ID=  pick a specific TppCredential by id (default: user's primary)

namespace :banking do
  desc "EnableBanking: start auth flow, print the URL to open in a browser"
  task start_auth: :environment do
    email = ENV["USER_EMAIL"].presence || abort("USER_EMAIL=... is required")
    aspsp = ENV["ASPSP"].presence       || abort("ASPSP=... is required")

    user = User.find_by!(email: email)
    credential =
      if ENV["CREDENTIAL_ID"].present?
        user.tpp_credentials.find(ENV["CREDENTIAL_ID"])
      else
        user.primary_tpp_credential
      end
    abort("User has no primary TppCredential. Pass CREDENTIAL_ID=... or set a primary.") unless credential

    if ENV["REDIRECT_URL"].present? && ENV["REDIRECT_URL"] != credential.redirect_url
      puts "redirect_url override (in-memory only): #{ENV['REDIRECT_URL']}"
      credential.redirect_url = ENV["REDIRECT_URL"]
    end

    form = BankConnectionRequestForm.new(
      aspsp_name:    aspsp,
      aspsp_country: ENV.fetch("COUNTRY", "PL"),
      psu_type:      ENV.fetch("PSU_TYPE", "personal"),
      valid_days:    ENV.fetch("DAYS", "180").to_i
    )
    abort("Invalid form: #{form.errors.full_messages.join(', ')}") unless form.valid?

    url = EnableBanking::Operations::StartAuth.call(
      credential:   credential,
      form:         form,
      current_user: user
    )

    puts ""
    puts "credential:   #{credential.name} (id=#{credential.id})"
    puts "redirect_url: #{credential.redirect_url}"
    puts ""
    puts "Open this URL in a browser and complete the bank login:"
    puts ""
    puts url
    puts ""
    puts "After login the bank redirects to #{credential.redirect_url}?code=...&state=..."
    puts "Copy code+state from the URL bar (page itself may fail to load - that's OK)."
    puts "Then run:"
    puts "  bin/rails banking:finish_auth CODE=... STATE=..."
  rescue EnableBanking::Operations::StartAuth::Failed => e
    abort "start_auth failed: #{e.message}"
  end

  desc "EnableBanking: complete auth, create BankConnection + BankAccounts from CODE/STATE"
  task finish_auth: :environment do
    code  = ENV["CODE"].presence  || abort("CODE=... is required")
    token = ENV["STATE"].presence || abort("STATE=... is required")

    state = EnableBanking::State.decode(token) ||
            abort("Invalid or expired state token (TTL is 30 minutes - re-run start_auth).")

    credential = TppCredential.find_by(id: state[:tpp_credential_id]) ||
                 abort("TPP credential from state no longer exists.")

    bc = EnableBanking::Operations::CreateConnection.call(
      credential: credential,
      code:       code,
      state:      state
    )

    puts ""
    puts "Connection created:"
    puts "  id:          #{bc.id}"
    puts "  bank:        #{bc.bank_name} (#{bc.bank_slug})"
    puts "  status:      #{bc.status}"
    puts "  psu_type:    #{bc.psu_type}"
    puts "  valid_until: #{bc.valid_until}"
    puts "  accounts:    #{bc.current_bank_accounts.count}"
    bc.current_bank_accounts.each do |a|
      puts "    - uid=#{a.uid.first(8)}...  iban=#{a.iban}  currency=#{a.currency}  name=#{a.name}"
    end
  rescue EnableBanking::Operations::CreateConnection::Failed => e
    abort "finish_auth failed: #{e.message}"
  end
end
