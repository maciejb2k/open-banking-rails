# frozen_string_literal: true

module Analytics
  # 3-sentence narrative card on top of the dashboard.
  #
  # Architecture is facts-only (ADR 0008): every number is computed in
  # Ruby; the LLM only writes the prose. A defensive numeric guard runs
  # after the model — every digit-sequence in the response must appear in
  # the serialized facts. Violations degrade silently to an empty string,
  # the view falls back to a muted callout.
  #
  # No cache in MVP1. Add fragment cache keyed by
  # (user_id, period.from, period.to, account_ids.sort.hash) when call
  # frequency justifies it.
  class AiInsight
    Result = Struct.new(:text, :facts, :status, :error_message, keyword_init: true) do
      def ok?         = status == :ok
      def empty?      = status == :empty
      def degraded?   = status == :degraded
    end

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[text],
      properties: {
        text: {
          type:        "string",
          description: "Exactly 3 sentences in Polish, neutral tone, no formatting."
        }
      }
    }.freeze

    def self.call(filter:, client: nil)
      new(filter: filter, client: client).call
    end

    def initialize(filter:, client: nil)
      @filter = filter
      @client = client || Llm::Client.default
    end

    def call
      facts = FactsBuilder.new(filter: @filter).call
      return Result.new(text: "", facts: facts, status: :empty) if facts[:spend_total_pln].zero?

      response = @client.structured(
        system_prompt: system_prompt,
        user_prompt:   user_prompt(facts),
        schema:        SCHEMA
      )

      text = response.fetch("text", "").to_s.strip
      return Result.new(text: "", facts: facts, status: :degraded, error_message: "blank response") if text.blank?

      unless NumericGuard.passes?(text: text, facts: facts)
        Rails.logger.warn("[Analytics::AiInsight] guard tripped: text=#{text.inspect}")
        return Result.new(text: "", facts: facts, status: :degraded, error_message: "numeric guard")
      end

      Result.new(text: text, facts: facts, status: :ok)
    rescue Llm::Client::Error => e
      Rails.logger.warn("[Analytics::AiInsight] LLM error: #{e.message}")
      Result.new(text: "", facts: nil, status: :degraded, error_message: e.message)
    end

    private

    def system_prompt
      <<~PROMPT
        Jesteś asystentem finansowym. Otrzymasz fakty o wydatkach użytkownika.
        Twoja rola: napisać DOKŁADNIE 3 zdania po polsku, ton informacyjny i
        neutralny (nie alarmistyczny, nie pochwalny).

        ZASADY (twarde):
        - Używaj WYŁĄCZNIE liczb obecnych w faktach. Nie wymyślaj kwot,
          procentów, nazw kategorii ani sprzedawców.
        - Jeśli faktów brakuje (np. brak prev_period_spend_pln), pomiń
          porównanie zamiast zgadywać.
        - Bez formatowania (bullet points, bold, emoji, nawiasy ostre).
        - Każde zdanie wnosi nowy fakt. Sugerowana struktura:
          (1) skala wydatków + delta vs poprzedni okres,
          (2) dominujący wzorzec (top_category lub top_merchant),
          (3) jeden notable_mover, lub komentarz o stabilności gdy ich brak.

        Zwracasz wyłącznie pole "text".
      PROMPT
    end

    def user_prompt(facts)
      "fakty:\n#{JSON.pretty_generate(facts)}"
    end
  end
end
