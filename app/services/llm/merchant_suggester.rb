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
        Z surowego tytułu transakcji wyciągasz nazwę sprzedawcy i wzorzec dopasowania.

        # ZASADY OGÓLNE

        ## Czym jest "merchant"
        Każda firma, sklep, platforma, fundacja, osoba prywatna lub instytucja, do której
        płynie pieniądz. Wszystko co da się nazwać własnym imieniem.

        ## Co odsiać z tytułu zanim zaczniesz identyfikację
        Polskie banki upakowują tytuł szumem. Zignoruj:
        - prefix miasta na początku (RZESZOW, WARSZAWA, KRAKOW, POZNAN, GDANSK, …)
        - trailing "PL" (kod kraju)
        - kody numeryczne terminali ("01", "7645", "RZ4")
        - prefiksy domen ("WWW.", "SKLEP.", "M.", "APP.")
        - sufiksy domen (".PL", ".COM", ".EU", ".NET")
        - separatory typu "*", "-", spacje wielokrotne
        Co zostaje to RDZEŃ — używaj go i jako merchant_name (z normalną kapitalizacją)
        i jako pattern.

        ## Klasy sprzedawców (rozpoznawaj klasą, nie listą marek)
        Każda transakcja należy do JEDNEJ z poniższych klas. Klasa narzuca strategię:

        1. **Sieć handlowa / sklep stacjonarny** — tytuł z prefiksem miasta i nazwą sieci.
           Strategia: pattern = nazwa sieci, kind=contains, field=title.

        2. **E-commerce / sklep internetowy** — tytuł zawiera domenę URL.
           Strategia: pattern = rdzeń domeny, kind=contains, field=title.

        3. **SaaS / subskrypcja cyfrowa** — counterparty_name niepuste, często z separatorem
           "*" oddzielającym wystawcę od produktu (Stripe-style).
           Strategia: pattern = rdzeń nazwy, kind=contains, field=counterparty_name.

        4. **Lokalna firma / pojedynczy punkt** — tytuł zawiera imię + nazwisko, nazwę
           niesieciową, lub branżową frazę. Może być nieznana wielkim modelom — to OK.
           Strategia: pattern = nazwa firmy bez prefiksu miasta, kind=contains, field=title.

        5. **Fundacja / NGO / charity** — domena .pl/.org z nazwą sugerującą cel społeczny
           ("FUNDACJA…", "RATUJEMY…", "POMOC…", "SIEPOMAGA"). kind=charity.
           Domyślna kategoria: gifts_donations.

        6. **Instytucja publiczna** — urząd, ZUS, US, sąd. kind=government.

        7. **Bilety / transport / parking** — często z nazwą operatora (PKP, mPay, SkyCash).

        ## Reguła (rule_pattern)
        Wzorzec musi dopasować WSZYSTKIE warianty tego sprzedawcy — różne miasta, różne
        terminale, różne końcówki domen. Zasada: krótki rdzeń, nie cały tytuł.
        - DOBRZE: pattern="LIDL"           (matchuje "RZESZOWLIDL 01PL", "WARSZAWALIDL 22PL", …)
        - DOBRZE: pattern="DEVSTYLE"       (matchuje "SKLEP.DEVSTYLE.PL", "WWW.DEVSTYLE.COM", …)
        - DOBRZE: pattern="Spotify"        (matchuje "Spotify P0E5C3F0F", "Spotify ABC123", …)
        - ŹLE:    pattern="RZESZOWLIDL 01PL"     (exact całego tytułu — przegapi inne terminale)
        - ŹLE:    pattern="LI"                   (zbyt krótki — false positivy na "LINIA", "LIST")
        kind=contains jest defaultem. exact tylko gdy counterparty_name to *czysto* nazwa firmy.
        kind=iban tylko gdy field=counterparty_iban.
        field=title dla mBank/PKO card-payment, field=counterparty_name dla SaaS / Revolut.

        ## Confidence — co znaczy każdy próg
        Confidence dotyczy *identyfikacji nazwy*, nie pewności kategorii. Niepewna kategoria
        nie obniża confidence — wybierz "uncategorized" i zostaw normalne conf dla nazwy.
        - 0.95+: rozpoznana sieć / domena / SaaS, zerowe wątpliwości.
        - 0.8–0.9: czytelny rdzeń (nieznana lokalnie marka, ale tytuł sam się tłumaczy).
        - 0.6–0.8: lokalna firma, niepełna nazwa, ale jest co dopasować.
        - <0.5: tytuł to sam kod numeryczny, "PRZELEW", "OBCY", lub jakiś bełkot bez nazwy
          → zwróć merchant_name="" i confidence=0. NIE wymyślaj nazwy.

        Asymetria: lepiej dać sensowny strzał z conf 0.7 niż defensywne 0. Niskie conf
        wpada do kolejki review, gdzie człowiek decyduje. Zerowe conf całkowicie tracimy.

        # KONTEKST

        ## Format mBank dla płatności kartą (przykład klasy 1)
        Tytuł: <MIASTO><NAZWA_SKLEPU><kod_terminala>PL.
        Po stripie miasta i "PL" + kodu zostaje czysta nazwa sieci.
        Przykład: "RZESZOWLIDL 01PL" → strip "RZESZOW" + "01PL" → "LIDL".

        ## Dostępne slugi kategorii
        #{available_category_slugs.join(", ")}
        Gdy żadna nie pasuje precyzyjnie — użyj "uncategorized".

        # WYJŚCIE
        Każdy element MUSI mieć pole `index` równe indeksowi wejściowemu — nawet
        gdy zwracasz pustą identyfikację.
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
