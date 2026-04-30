# frozen_string_literal: true

namespace :cash do
  desc "Link historical BLIK ATM withdrawals to cash wallets for users with track_cash=true"
  task backfill_atm_links: :environment do
    total_users = 0
    total_linked = 0
    total_skipped = 0

    User.where(track_cash: true).find_each do |user|
      total_users += 1
      linked = 0
      skipped = 0

      BankTransaction.for_user(user)
                     .where(payment_method: "blik_atm", direction: "debit")
                     .find_each do |tx|
        if Cash::AtmWithdrawalLinker.link!(tx)
          linked += 1
        else
          skipped += 1
        end
      end

      total_linked += linked
      total_skipped += skipped
      puts "  user=#{user.email}  linked=#{linked}  already-linked-or-noop=#{skipped}"
    end

    puts ""
    puts "users processed: #{total_users}"
    puts "newly linked:    #{total_linked}"
    puts "no-ops:          #{total_skipped}"
    puts ""
    if total_linked.positive?
      puts "Reminder: balances of cash wallets now reflect the sum of historical"
      puts "withdrawals. Reconcile against your physical wallet via the UI"
      puts "(Phase 4) to record the difference as a one-time adjustment."
    end
  end
end
