# frozen_string_literal: true

namespace :banking do
  desc "Backfill counterparty_kind on every existing BankTransaction + ManualTransaction"
  task backfill_counterparty_kind: :environment do
    total_users = 0
    bank_updated = 0
    manual_updated = 0

    User.find_each do |user|
      total_users += 1

      BankTransaction.for_user(user).find_each do |tx|
        kind = Banking::CounterpartyResolver.for(tx, user: user)
        next if tx.counterparty_kind == kind
        tx.update_column(:counterparty_kind, kind)
        bank_updated += 1
      end

      ManualTransaction.for_user(user).find_each do |tx|
        kind = Banking::CounterpartyResolver.for(tx, user: user)
        next if tx.counterparty_kind == kind
        tx.update_column(:counterparty_kind, kind)
        manual_updated += 1
      end

      puts "  user=#{user.email}"
    end

    puts ""
    puts "users processed:           #{total_users}"
    puts "bank rows updated:         #{bank_updated}"
    puts "manual rows updated:       #{manual_updated}"
  end

  desc "Re-run PaymentMethodInferer over existing BankTransactions (use after extending TYPE_HINT_MAP) and rebuild affected enrichments. Pass DRY_RUN=1 to preview without writing."
  task backfill_payment_methods: :environment do
    dry_run = ENV["DRY_RUN"].to_s == "1"
    puts "DRY RUN — no changes will be persisted." if dry_run

    total_users    = 0
    pm_updated     = 0
    cpk_updated    = 0
    rebuilt_users  = 0
    by_transition  = Hash.new(0)

    User.find_each do |user|
      total_users += 1
      changed_in_user = 0

      BankTransaction.for_user(user).find_in_batches(batch_size: 500) do |batch|
        batch.each do |tx|
          new_pm = EnableBanking::PaymentMethodInferer.call(
            type_hint:             tx.type_hint,
            bank_transaction_code: tx.bank_transaction_code,
            title:                 tx.title,
            counterparty_name:     tx.counterparty_name,
            direction:             tx.direction
          )
          next if tx.payment_method == new_pm

          by_transition[[ tx.type_hint, tx.payment_method, new_pm ]] += 1
          pm_updated += 1
          changed_in_user += 1

          next if dry_run

          tx.update_column(:payment_method, new_pm)

          new_kind = Banking::CounterpartyResolver.for(tx, user: user)
          if tx.counterparty_kind != new_kind
            tx.update_column(:counterparty_kind, new_kind)
            cpk_updated += 1
          end
        end
      end

      if changed_in_user.positive? && !dry_run
        Enrichment::TransactionEnricher.rebuild!(user: user)
        rebuilt_users += 1
      end

      puts "  user=#{user.email}  payment_method_changes=#{changed_in_user}"
    end

    puts ""
    if by_transition.any?
      puts "Transitions:"
      by_transition.sort_by { |_, n| -n }.each do |(type_hint, old_pm, new_pm), n|
        puts "  #{n.to_s.rjust(6)}  type_hint=#{type_hint.inspect}  #{old_pm.inspect} -> #{new_pm.inspect}"
      end
      puts ""
    end
    puts "users processed:                 #{total_users}"
    puts "payment_method #{dry_run ? 'would update' : 'updates'}:       #{pm_updated}"
    puts "counterparty_kind #{dry_run ? 'would update' : 'updates'}:    #{cpk_updated}" unless dry_run
    puts "users with enrichments rebuilt:  #{rebuilt_users}" unless dry_run
    puts ""
    puts "Re-run without DRY_RUN=1 to apply." if dry_run && pm_updated.positive?
  end
end
