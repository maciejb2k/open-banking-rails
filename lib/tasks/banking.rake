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
end
