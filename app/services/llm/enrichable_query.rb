# frozen_string_literal: true

module Llm
  # "Which transactions can the LLM still help with?" — query object owning
  # both the SQL scope and the Ruby-side grouping (deduplication by
  # normalized title + counterparty_name) used by the enrichment runner.
  #
  # Consolidating these here means the dashboard counters and the runner's
  # actual workload can never drift apart — the index page asks the same
  # query the job will execute. Previously both controllers were reaching
  # into `Llm::EnrichmentRunner.new.send(:default_scope)`, which leaked a
  # private API and made the runner the de-facto owner of a query that
  # belongs to neither it nor a controller.
  #
  # Excluded payment methods (`NON_MERCHANT_PAYMENT_METHODS`) are kinds for
  # which "merchant" is a category error: BLIK to a phone is a transfer
  # between people, ATM is a cash withdrawal, internal transfers / topups
  # move money within your own accounts, fees are bank charges. Sending
  # them to the LLM produces noise at best ("John Doe is a merchant" —
  # nope, that's the user) and bad rules at worst.
  #
  # Counterparty kind `self` filters out own-account moves — same rationale,
  # set at sync time by Banking::CounterpartyResolver.
  class EnrichableQuery
    NON_MERCHANT_PAYMENT_METHODS = %w[blik_p2p blik_atm internal_transfer topup fee].freeze

    def self.scope(user:)         = new(user).scope
    def self.groups(user:, scope: nil) = new(user).groups(scope: scope)

    def initialize(user)
      @user = user
    end

    # Anything without a merchant (source = unmatched OR system_fallback)
    # AND that could plausibly have one. The title regex
    # (`!~ '^[0-9]+$'`) drops rows whose title is purely numeric — those
    # are BLIK codes / reference numbers, not merchant signal.
    def scope
      BankTransaction.for_user(@user)
        .joins(:enrichment)
        .merge(TransactionEnrichment.merchantless)
        .where("(title IS NOT NULL AND title <> '' AND title !~ '^[0-9]+$') OR (counterparty_name IS NOT NULL AND counterparty_name <> '')")
        .where.not(payment_method: NON_MERCHANT_PAYMENT_METHODS)
        .where.not(counterparty_kind: "self")
    end

    # Group eligible transactions by (normalized_title, counterparty_name)
    # and skip those already covered by an existing MerchantRule
    # (regardless of enabled/source) — sending them to the LLM would yield
    # the same suggestion and waste tokens. User must accept the existing
    # pending merchant to release the group.
    #
    # Returns { [normalized_title, counterparty_name] => { title:, counterparty_name: } }.
    # The caller decides ordering and limit.
    def groups(scope: nil)
      relation = scope || self.scope
      rules    = @user.merchant_rules.to_a

      relation.find_each.each_with_object({}) do |tx, acc|
        key = [ Enrichment::TitleNormalizer.call(tx.title), tx.counterparty_name.to_s ]
        next if key == [ "", "" ]
        next if covered_by_existing_rule?(rules, tx)
        acc[key] ||= { title: tx.title, counterparty_name: tx.counterparty_name }
      end
    end

    private

    def covered_by_existing_rule?(rules, tx)
      rules.any? do |r|
        value = case r.field
        when "title"             then tx.title
        when "counterparty_name" then tx.counterparty_name
        when "counterparty_iban" then tx.counterparty_iban
        end
        value.present? && r.matches?(value)
      end
    end
  end
end
