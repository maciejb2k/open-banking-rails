# frozen_string_literal: true

# == Schema Information
#
# Table name: manual_transactions
#
#  id                         :bigint           not null, primary key
#  amount_cents               :bigint           not null
#  booking_date               :date             not null
#  counterparty_kind          :string           default("unknown"), not null
#  counterparty_name          :string
#  currency                   :string(3)        not null
#  direction                  :string           not null
#  note                       :text
#  payment_method             :string
#  source                     :string           default("manual"), not null
#  status                     :string           default("booked"), not null
#  title                      :text
#  transaction_date           :date
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  bank_account_id            :bigint           not null
#  created_by_user_id         :bigint           not null
#  linked_bank_transaction_id :bigint
#
# Indexes
#
#  idx_manual_transactions_one_per_linked_bank_tx                 (linked_bank_transaction_id) UNIQUE WHERE (linked_bank_transaction_id IS NOT NULL)
#  index_manual_transactions_on_bank_account_id                   (bank_account_id)
#  index_manual_transactions_on_bank_account_id_and_booking_date  (bank_account_id,booking_date)
#  index_manual_transactions_on_counterparty_kind                 (counterparty_kind)
#  index_manual_transactions_on_created_by_user_id                (created_by_user_id)
#  index_manual_transactions_on_linked_bank_transaction_id        (linked_bank_transaction_id)
#  index_manual_transactions_on_payment_method                    (payment_method)
#  index_manual_transactions_on_status                            (status)
#
# Foreign Keys
#
#  fk_rails_...  (bank_account_id => bank_accounts.id)
#  fk_rails_...  (created_by_user_id => users.id)
#  fk_rails_...  (linked_bank_transaction_id => bank_transactions.id)
#
FactoryBot.define do
  factory :manual_transaction do
    transient do
      user { association :user }
    end

    bank_account     { association :bank_account, :cash, manual_owner: user }
    created_by_user  { user }
    amount_cents     { 50_00 }
    currency         { "PLN" }
    direction        { "debit" }
    status           { "booked" }
    payment_method   { "cash" }
    source           { "manual" }
    counterparty_kind { "unknown" }
    booking_date     { Date.current }
    transaction_date { Date.current }
    title            { "Cash entry" }

    trait :pln do
      currency { "PLN" }
    end

    trait :eur do
      currency       { "EUR" }
      bank_account   { association :bank_account, :cash, manual_owner: user, currency: "EUR" }
    end

    trait :linked do
      transient do
        linked_bank_transaction { association :bank_transaction, :atm_withdrawal }
      end
      linked_bank_transaction_id { linked_bank_transaction.id }
      source                     { "atm_link" }
    end
  end
end
