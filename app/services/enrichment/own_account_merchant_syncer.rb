# frozen_string_literal: true

module Enrichment
  # Lets the enricher recognize own-IBAN transfers (Revolut PL exposes a
  # second LT IBAN for the same account, hence the alternates list).
  # Idempotent: removed IBANs disable their rules, never delete (historical
  # enrichments reference merchant_rule_id).
  #
  # Priority 200 beats seeded retail rules (default 0) within source=system -
  # so own-IBAN match wins against a generic title keyword like "JOHN DOE" on
  # outgoing PKO transfers. User-source rules still override.
  class OwnAccountMerchantSyncer
    OWN_TRANSFER_CATEGORY_SLUG = "transfers"
    RULE_PRIORITY              = 200

    def self.call(bank_account) = new(bank_account).call

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

    def account_user
      @account_user ||= @bank_account.tpp_credential&.user ||
                        (@bank_account.manual_owner_id && User.find_by(id: @bank_account.manual_owner_id))
    end

    # Stable per account uid - survives display_name changes; deletes leave
    # historical enrichments on a dead slug rather than colliding.
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
