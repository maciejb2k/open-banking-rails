# frozen_string_literal: true

module Analytics
  # Verifies that every digit-sequence in an LLM-generated text is also
  # present in the serialized facts. This is the safety net behind the
  # facts-only contract (ADR 0008): if the model invents a number, the
  # check fails and the view falls back to an empty card.
  #
  # The check is intentionally lossy — it only prevents *invented* digits,
  # not subtle misuse of correct ones (saying a category is rising when
  # it's falling, etc.). Plain text is hard to fully gate; the prompt does
  # most of the work, this is the lower bound.
  module NumericGuard
    NUMBER_RE = /\d+(?:[.,]\d+)?/

    def self.passes?(text:, facts:)
      allowed = digit_sequences(facts)
      text.scan(NUMBER_RE).all? { |found| allowed.include?(normalize(found)) }
    end

    def self.digit_sequences(facts)
      JSON.generate(facts).scan(NUMBER_RE).map { |s| normalize(s) }.to_set
    end

    # Treat "1234.5" and "1234,5" as equal — Polish copy uses the comma,
    # JSON uses the dot. Without normalization a perfectly-quoted figure
    # would trip the guard.
    def self.normalize(str)
      str.tr(",", ".")
    end
  end
end
