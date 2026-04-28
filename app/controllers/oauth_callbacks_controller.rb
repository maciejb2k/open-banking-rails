# frozen_string_literal: true

# Receives the redirect from the bank after PSU authorizes a session.
# Verifies signed `state`, exchanges `code` for a session via CreateSession,
# then materializes BankConnection + BankAccount records in a single
# transaction.
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

    result = EnableBanking::Queries::CreateSession.call(credential: credential, code: params[:code])

    if result.success?
      bc = build_records(credential, state, result.data)
      redirect_to admin_settings_bank_connection_path(bc),
                  notice: "Bank connected — #{bc.bank_name}, #{bc.current_bank_accounts.count} account(s)."
    else
      reject("Could not create session: #{result.error.presence || "HTTP #{result.status}"}")
    end
  rescue EnableBanking::Error => e
    reject("Configuration error: #{e.message}")
  rescue ActiveRecord::RecordInvalid => e
    reject("Could not save records: #{e.message}")
  end

  private

  def reject(reason)
    redirect_to admin_settings_bank_connections_path, alert: reason
  end

  def build_records(credential, state, payload)
    BankConnection.transaction do
      old_connection = find_replaces_target(credential, state)

      bc = credential.bank_connections.create!(
        bank_slug: state[:aspsp_name].to_s.parameterize(separator: "_"),
        bank_country: state[:aspsp_country] || payload.dig("aspsp", "country"),
        bank_name: payload.dig("aspsp", "name") || state[:aspsp_name],
        status: "authorized",
        psu_type: payload["psu_type"] || state[:psu_type],
        session_id: payload["session_id"],
        psu_id_hash: payload["psu_id_hash"],
        access_balances: payload.dig("access", "balances"),
        access_transactions: payload.dig("access", "transactions"),
        valid_until: payload.dig("access", "valid_until"),
        authorized_at: payload["authorized"] || Time.current,
        raw_session_payload: payload.to_json,
        replaces: old_connection
      )

      Array(payload["accounts"]).each do |account|
        next unless account.is_a?(Hash) && account["uid"].present?

        ba = BankAccount.find_or_initialize_by(uid: account["uid"])
        ba.assign_attributes(
          tpp_credential: credential,
          current_bank_connection: bc,  # repoint to new connection (old stays in DB)
          iban: account.dig("account_id", "iban"),
          bban: BankAccount.bban_from(account["account_id"]),
          all_account_ids: account["all_account_ids"] || [],
          currency: account["currency"],
          name: account["name"].presence || ba.name,
          product: account["product"] || ba.product,
          details: account["details"] || ba.details,
          cash_account_type: account["cash_account_type"] || ba.cash_account_type,
          usage: account["usage"] || ba.usage,
          status: "active",
          account_servicer: account["account_servicer"] || ba.account_servicer,
          raw_account_resource: account
        )
        ba.save!
      end

      # Mark replaced connection — KEEP the record (audit trail), don't destroy.
      # Accounts that were on the new payload have already been re-pointed above.
      # Accounts NOT in the new payload (user deselected them at the bank) keep
      # their old current_bank_connection_id — they appear "stale" in the UI
      # and stop syncing, but historical data is preserved.
      old_connection&.update!(status: "replaced", closed_at: Time.current)

      bc
    end
  end

  # Resolve `replaces_connection_id` from the signed state, scoped to the
  # current credential. Returns nil if missing or if it points to a connection
  # that doesn't belong to this credential (defense-in-depth).
  def find_replaces_target(credential, state)
    id = state[:replaces_connection_id]
    return nil if id.blank?
    credential.bank_connections.find_by(id: id)
  end
end
