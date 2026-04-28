# frozen_string_literal: true

# Receives the redirect from the bank after PSU authorizes a session.
# Verifies signed `state`, then delegates to Operations::CreateConnection
# which exchanges the auth code and materializes BankConnection +
# BankAccount records in a single transaction.
#
# The route (`/callback`) must match the redirect_url registered with the
# provider AND with the user's TppCredential.redirect_url. If those differ,
# the bank rejects the auth flow before it ever reaches us.
class OauthCallbacksController < ApplicationController
  before_action :authenticate_user!

  def enable_banking
    return reject("Authorization was cancelled or failed at the bank.") if params[:error].present?

    state = EnableBanking::State.decode(params[:state])
    return reject("Invalid or expired state. Start the flow again.") unless state
    return reject("State user mismatch.") unless state[:user_id] == current_user.id
    return reject("Authorization code missing.") if params[:code].blank?

    credential = current_user.tpp_credentials.find_by(id: state[:tpp_credential_id])
    return reject("TPP credential no longer exists.") unless credential

    bc = EnableBanking::Operations::CreateConnection.call(
      credential: credential,
      code: params[:code],
      state: state
    )

    redirect_to admin_settings_bank_connection_path(bc),
                notice: "Bank connected — #{bc.bank_name}, #{bc.current_bank_accounts.count} account(s)."
  rescue EnableBanking::Operations::CreateConnection::Failed => e
    reject(e.message)
  end

  private

  def reject(reason)
    redirect_to admin_settings_bank_connections_path, alert: reason
  end
end
