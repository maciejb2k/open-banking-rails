# frozen_string_literal: true

# Adds a derived `payment_method` column to bank_transactions.
#
# This is normalization, not enrichment - the value is a deterministic
# function of bank-supplied fields (type_hint, bank_transaction_code, title)
# and is computed in TransactionNormalizer at sync time. It lives on the
# bank_transactions table (not transaction_enrichments) because it's
# re-derivable from raw_payload alone and shouldn't get wiped by an
# enrichment rebuild.
#
# Possible values (see PaymentMethodInferer):
#   card | blik_pos | blik_p2p | blik_atm | transfer | p2p_transfer
#   card_recurring | card_authorization | fee | internal_transfer | other
class AddPaymentMethodToBankTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :bank_transactions, :payment_method, :string
    add_index  :bank_transactions, :payment_method
  end
end
