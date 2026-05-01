# frozen_string_literal: true

module Enrichment
  # Per-BankAccount "Own account" merchant with iban-kind MerchantRules
  # covering every IBAN that account is known by (primary + alternates from
  # the bank — Revolut PL exposes a second LT IBAN for that same account).
  #
  # The whole point: when `counterparty_iban` on an inbound/outbound tx
  # matches one of the user's own IBANs, the enricher recognizes it as a
  # transfer between own accounts — not an expense, not a private p2p, not
  # a fallback bucket. That's what lets `Category#kind == 'transfer'`
  # cleanly exclude these from spend analytics.
  #
  # Idempotent on every dimension:
  #   - Re-running on the same account: same merchant slug, no duplicate rules.
  #   - IBAN added (rare): new rule appended, others untouched.
  #   - IBAN removed (rare): old rule disabled (not deleted) so historical
  #     enrichments keep their merchant_rule_id link.
  #
  # Priority is set above seeded retail rules (200 vs default 0) so within
  # source=system, an own-IBAN match beats a generic title-keyword like
  # "JOHN DOE" that some PKO outgoing transfers carry. User-source rules
  # still override (different SOURCE_RANK tier).
  class OwnAccountMerchantSyncer
    OWN_TRANSFER_CATEGORY_SLUG = "transfers"
    RULE_PRIORITY              = 200

    def self.call(bank_account) = new(bank_account).call

    # Bulk entrypoint for backfills + a one-time bootstrap. Ignores accounts
    # without a primary IBAN (shouldn't happen post-sync, but defensive).
    def self.sync_all(scope: BankAccount.all)
      scope.find_each.map { |acc| call(acc) }.compact
    end

    def initialize(bank_account)
      @bank_account = bank_account
    end

    def call
      ibans = collect_ibans
      return nil if ibans.empty?

      ActiveRecord::Base.transaction do
        merchant = upsert_merchant
        sync_rules(merchant, ibans)
        merchant
      end
    end

    private

    def collect_ibans
      ([ @bank_account.iban ] + @bank_account.alternate_ibans)
        .compact_blank
        .map { |i| i.to_s.gsub(/\s+/, "").upcase }
        .uniq
    end

    def upsert_merchant
      user = account_user
      raise "BankAccount #{@bank_account.id} has no resolvable owner" if user.nil?

      merchant = user.merchants.find_or_initialize_by(slug: merchant_slug)
      merchant.assign_attributes(
        name:             merchant_name,
        kind:             "person",
        source:           "system",
        default_category: user.categories.find_by!(slug: OWN_TRANSFER_CATEGORY_SLUG),
        notes:            "Auto-generated. Matches transfers where counterparty_iban is one of #{@bank_account.display_name}'s own IBANs.",
        approved_at:      merchant.approved_at || Time.current
      )
      merchant.save!
      merchant
    end

    # Account owner: synced accounts go through tpp_credential, manual cash
    # wallets through manual_owner_id. Single source of truth so we don't
    # have to special-case both call sites.
    def account_user
      @account_user ||= @bank_account.tpp_credential&.user ||
                        (@bank_account.manual_owner_id && User.find_by(id: @bank_account.manual_owner_id))
    end

    # Stable per account uid — survives display_name changes, deletes leave
    # historical enrichments pointing at a known-dead slug rather than a
    # collision with another account.
    def merchant_slug
      "own_account_#{@bank_account.uid.to_s[0, 8]}"
    end

    def merchant_name
      bank_label = @bank_account.current_bank_connection&.bank_name.presence ||
                   @bank_account.tpp_credential&.name.presence ||
                   "Bank"
      last4 = @bank_account.iban.to_s[-4..].presence || "????"
      "Own account (#{bank_label} ⋯#{last4})"
    end

    # Reconcile against existing rules so re-runs don't churn rows. Rules
    # for IBANs no longer present get disabled — never deleted, since
    # transaction_enrichments may reference them.
    def sync_rules(merchant, ibans)
      existing = merchant.merchant_rules
                         .where(kind: "iban", field: "counterparty_iban")
                         .index_by(&:pattern)

      ibans.each do |iban|
        rule = existing[iban] || merchant.merchant_rules.build(
          kind: "iban", field: "counterparty_iban", pattern: iban
        )
        rule.assign_attributes(
          user:          merchant.user,
          source:        "system",
          enabled:       true,
          priority:      RULE_PRIORITY,
          case_sensitive: false,
          approved_at:   rule.approved_at || Time.current
        )
        rule.save!
      end

      stale = existing.keys - ibans
      merchant.merchant_rules.where(pattern: stale).update_all(enabled: false) if stale.any?
    end
  end
end
