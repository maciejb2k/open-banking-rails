# frozen_string_literal: true

# Populates `payment_method` for transactions synced before the column
# existed. Uses the same PaymentMethodInferer that runs at sync time, so
# results match what new rows get going forward.
#
# Idempotent: only touches rows where payment_method is NULL.
class BackfillPaymentMethodOnBankTransactions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Wait until the model has the new column visible.
    BankTransaction.reset_column_information

    BankTransaction.where(payment_method: nil).find_each do |tx|
      method = EnableBanking::PaymentMethodInferer.call(
        type_hint: tx.type_hint,
        bank_transaction_code: tx.bank_transaction_code,
        title: tx.title,
        counterparty_name: tx.counterparty_name,
        direction: tx.direction
      )
      tx.update_columns(payment_method: method) if method
    end
  end

  def down
    BankTransaction.update_all(payment_method: nil)
  end
end
