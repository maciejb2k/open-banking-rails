# frozen_string_literal: true

# One-off cleanup for BankAccount rows duplicated by EnableBanking re-auth
# (EB reissues account UIDs across sessions, so the old upsert logic created
# a fresh row instead of re-attaching the existing one).
#
# Workflow on the pod:
#   bin/rails banking:diagnose_duplicate_accounts
#   bin/rails banking:merge_duplicate_accounts CANONICAL_ID=<keep> DUP_ID=<drop>
#   bin/rails banking:merge_duplicate_accounts CANONICAL_ID=<keep> DUP_ID=<drop> CONFIRM=1

namespace :banking do
  desc "Scan for duplicate BankAccount rows (same IBAN under same TppCredential)"
  task diagnose_duplicate_accounts: :environment do
    groups = BankAccount.synced.where.not(iban: [ nil, "" ])
                        .group_by { |a| [ a.tpp_credential_id, a.iban ] }
                        .select { |_, rows| rows.size > 1 }

    if groups.empty?
      puts "No duplicates found."
      next
    end

    groups.sort_by { |(cred_id, iban), _| [ cred_id, iban ] }.each do |(cred_id, iban), accounts|
      cred = TppCredential.find(cred_id)
      puts ""
      puts "USER #{cred.user.email}  CREDENTIAL #{cred.name} (id=#{cred.id})"
      puts "  IBAN #{iban}:"
      accounts.sort_by(&:id).each do |a|
        conn = a.current_bank_connection
        bank = conn ? "#{conn.bank_name} (#{conn.status}, conn_id=#{conn.id})" : "—"
        puts "    [id=#{a.id}]  uid=#{a.uid.first(8)}...  #{bank}  bank_tx=#{a.bank_transactions.count}  manual_tx=#{a.manual_transactions.count}  created=#{a.created_at.to_date}"
      end
    end

    puts ""
    puts "To merge: bin/rails banking:merge_duplicate_accounts CANONICAL_ID=<keep> DUP_ID=<drop>"
    puts "         (defaults to dry-run; add CONFIRM=1 to actually write)"
  end

  desc "Merge a duplicate BankAccount into a canonical one. DRY_RUN by default; CONFIRM=1 to apply."
  task merge_duplicate_accounts: :environment do
    canonical_id = ENV["CANONICAL_ID"].presence&.to_i || abort("CANONICAL_ID=... required (the BankAccount to keep)")
    dup_id       = ENV["DUP_ID"].presence&.to_i       || abort("DUP_ID=... required (the BankAccount to drop)")
    confirm      = ENV["CONFIRM"] == "1"

    canonical = BankAccount.find(canonical_id)
    dup       = BankAccount.find(dup_id)

    abort("Refusing: same record.") if canonical.id == dup.id
    abort("Refusing: canonical has no IBAN.") if canonical.iban.blank?
    abort("Refusing: IBAN mismatch (#{canonical.iban} vs #{dup.iban}).") unless canonical.iban == dup.iban
    abort("Refusing: tpp_credential mismatch (#{canonical.tpp_credential_id} vs #{dup.tpp_credential_id}).") unless canonical.tpp_credential_id == dup.tpp_credential_id
    abort("Refusing: dup is a cash wallet, not a synced account.") if dup.manual?

    canonical_external_ids = canonical.bank_transactions.pluck(:external_id)
    colliding     = dup.bank_transactions.where(external_id: canonical_external_ids)
    unique_to_dup = dup.bank_transactions.where.not(external_id: canonical_external_ids)

    puts "Merge plan:"
    puts "  canonical: id=#{canonical.id}  uid=#{canonical.uid}  conn_id=#{canonical.current_bank_connection_id}  created=#{canonical.created_at.to_date}"
    puts "  dup:       id=#{dup.id}  uid=#{dup.uid}  conn_id=#{dup.current_bank_connection_id}  created=#{dup.created_at.to_date}"
    puts "  IBAN:      #{canonical.iban}"
    puts ""
    puts "Transactions on dup:"
    puts "    bank_tx total:                       #{dup.bank_transactions.count}"
    puts "      will delete (external_id collide): #{colliding.count}"
    puts "      will re-point to canonical:        #{unique_to_dup.count}"
    puts "    manual_tx total (all re-pointed):    #{dup.manual_transactions.count}"
    puts ""
    puts "After merge, canonical inherits:"
    puts "    uid:                     #{canonical.uid} -> #{dup.uid}" if canonical.uid != dup.uid
    puts "    current_bank_connection: #{canonical.current_bank_connection_id} -> #{dup.current_bank_connection_id}" if canonical.current_bank_connection_id != dup.current_bank_connection_id

    unless confirm
      puts ""
      puts "DRY RUN. Re-run with CONFIRM=1 to apply."
      next
    end

    BankAccount.transaction do
      colliding.destroy_all
      unique_to_dup.update_all(bank_account_id: canonical.id)
      dup.manual_transactions.update_all(bank_account_id: canonical.id)

      new_uid     = dup.uid
      new_conn_id = dup.current_bank_connection_id
      new_all_ids = dup.all_account_ids
      new_srv     = dup.account_servicer
      new_raw     = dup.raw_account_resource

      dup.destroy!

      canonical.update!(
        uid: new_uid,
        current_bank_connection_id: new_conn_id,
        all_account_ids: new_all_ids.presence || canonical.all_account_ids,
        account_servicer: new_srv || canonical.account_servicer,
        raw_account_resource: new_raw || canonical.raw_account_resource
      )
    end

    puts ""
    puts "Done. canonical id=#{canonical.id} now carries the new connection (#{canonical.current_bank_connection_id})."
    puts "The old connection that originally created the canonical may still be in 'authorized' status -"
    puts "close it from the admin UI if you don't need it as a historical record."
  end
end
