# frozen_string_literal: true

module Llm
  # Asks the LLM to identify merchants from a batch of raw transaction titles +
  # counterparty names, and propose matching rules we can persist.
  #
  # Sends up to BATCH_SIZE items in one API call — each item gets an `index`
  # so results can be matched back even if the model reorders or skips some.
  #
  # Privacy: only `title` and `counterparty_name` are ever sent.
  class MerchantSuggester
    BATCH_SIZE = 15

    Result = Struct.new(:merchant_name, :merchant_kind, :category_slug, :rule_field, :rule_kind, :rule_pattern, :confidence, :reasoning, keyword_init: true) do
      def confident?(threshold = 0.85)
        confidence.to_f >= threshold
      end
    end

    ITEM_SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[index merchant_name merchant_kind category_slug rule_field rule_kind rule_pattern confidence reasoning],
      properties: {
        index:         { type: "integer", description: "Same index as the input item." },
        merchant_name: { type: "string",  description: "Canonical merchant name. Empty string if unidentifiable." },
        merchant_kind: { type: "string",  enum: %w[company person charity government platform other unknown] },
        category_slug: { type: "string",  description: "Slug from the provided category list. 'uncategorized' if unsure." },
        rule_field:    { type: "string",  enum: %w[title counterparty_name counterparty_iban] },
        rule_kind:     { type: "string",  enum: %w[contains regex exact prefix iban] },
        rule_pattern:  { type: "string",  description: "Short substring that uniquely identifies the merchant across location variants." },
        confidence:    { type: "number",  minimum: 0, maximum: 1 },
        reasoning:     { type: "string",  description: "One short sentence explaining the choice." }
      }
    }.freeze

    BATCH_SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[results],
      properties: {
        results: { type: "array", items: ITEM_SCHEMA }
      }
    }.freeze

    # Single-item interface kept for tests / manual use.
    def self.call(title:, counterparty_name: nil, client: nil)
      batch_call([ { title: title, counterparty_name: counterparty_name } ], client: client).first
    end

    # Primary interface for EnrichmentRunner.
    # items: array of { title:, counterparty_name: }
    # Returns array of Result in the same order as items.
    def self.batch_call(items, client: nil)
      new(items: items, client: client).call
    end

    # Last-call I/O — exposed so callers can log the actual prompt/response
    # for debugging without re-running the model.
    attr_reader :last_input, :last_response

    def initialize(items:, client: nil)
      @items  = items
      @client = client || Llm::Client.default
    end

    def call
      @last_input    = @items.each_with_index.map { |i, idx| { "index" => idx, "title" => i[:title].to_s, "counterparty_name" => i[:counterparty_name].to_s } }
      @last_response = @client.structured(
        system_prompt: system_prompt,
        user_prompt:   user_prompt,
        schema:        BATCH_SCHEMA
      )

      indexed = Array(@last_response["results"]).index_by { |r| r["index"].to_i }

      @items.each_with_index.map do |_item, idx|
        r = indexed[idx]
        r ? build_result(r) : null_result
      end
    end

    private

    def system_prompt
      <<~PROMPT
        Jesteś asystentem klasyfikującym transakcje z polskich banków (mBank, PKO, Revolut).
        Identyfikujesz sprzedawców z surowych tytułów transakcji.

        ## Format mBank dla płatności kartą
        Tytuł ma postać: <MIASTO><NAZWA_SKLEPU><kod_lokalizacji>PL
        Przykłady:
        - "RZESZOWLIDL 01PL"               → Lidl
        - "RZESZOWJMP S.A. BIEDRONKA 7645PL" → Biedronka  (JMP S.A. to spółka, nazwa to Biedronka)
        - "RzeszoweLeclercPL"              → eLeclerc
        - "RZESZOWAUCHAN PODWISLOCZEPL"    → Auchan (Podwisłocze to lokalizacja)
        - "WARSZAWAT-MOBILE POLSKAPL"      → T-Mobile
        - "RZESZOWOTCF RZ4PL"              → 4F (OTCF to spółka-matka 4F)

        ## SaaS / subskrypcje
        Często mają `counterparty_name` i puste type_hint. Trzymaj nazwę kanoniczną:
        - "Claude.ai Subscription"  → Claude.ai
        - "Openai *chatgpt Subscr"  → OpenAI
        - "Google *google One"      → Google One

        ## Reguła
        Generuj wzorzec, który dopasuje WSZYSTKIE warianty tego sprzedawcy z różnymi numerami lokalizacji.
        Dla "RZESZOWLIDL 01PL" wzorzec to po prostu "LIDL" (kind: contains, field: title).
        Dla "Claude.ai Subscription" wzorzec to "Claude.ai" na polu counterparty_name.

        ## Confidence
        - 0.95+: rozpoznana znana sieć (Biedronka, Lidl, Claude.ai itp.)
        - 0.7-0.9: sensowna identyfikacja, ale niepewna nazwa lub kategoria
        - <0.7: zgaduję — lepiej nie tworzyć reguły

        ## Dostępne slugi kategorii
        #{available_category_slugs.join(", ")}

        Zwracaj tylko polskie nazwy własne sprzedawców (zachowaj oryginalną pisownię).
        Jeśli nie umiesz zidentyfikować — `merchant_name: ""`, `confidence: 0`.
        Każdy element wyjściowy MUSI mieć pole `index` równe indeksowi wejściowemu.
      PROMPT
    end

    def user_prompt
      lines = @items.each_with_index.map do |item, idx|
        parts = [ "index: #{idx}", "title: #{item[:title].to_s.inspect}" ]
        parts << "counterparty_name: #{item[:counterparty_name].to_s.inspect}" if item[:counterparty_name].present?
        "{ #{parts.join(", ")} }"
      end
      "Sklasyfikuj poniższe transakcje:\n[\n  #{lines.join(",\n  ")}\n]"
    end

    def available_category_slugs
      Category.active.pluck(:slug).sort
    end

    def build_result(raw)
      Result.new(
        merchant_name: raw["merchant_name"].to_s.strip,
        merchant_kind: raw["merchant_kind"].to_s.presence || "unknown",
        category_slug: raw["category_slug"].to_s.presence || "uncategorized",
        rule_field:    raw["rule_field"].to_s.presence || "title",
        rule_kind:     raw["rule_kind"].to_s.presence || "contains",
        rule_pattern:  raw["rule_pattern"].to_s.strip,
        confidence:    raw["confidence"].to_f,
        reasoning:     raw["reasoning"].to_s
      )
    end

    def null_result
      Result.new(
        merchant_name: "", merchant_kind: "unknown", category_slug: "uncategorized",
        rule_field: "title", rule_kind: "contains", rule_pattern: "",
        confidence: 0.0, reasoning: "LLM did not return a result for this index."
      )
    end
  end
end
