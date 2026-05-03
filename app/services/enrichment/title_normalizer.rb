# frozen_string_literal: true

module Enrichment
  # mBank prepends the city to card-payment titles. Examples:
  #   RZESZOWLIDL 01PL                  → "LIDL"
  #   RZESZOWJMP S.A. BIEDRONKA 7645PL  → "JMP S.A. BIEDRONKA"
  #   RzeszoweLeclercPL                 → "LECLERC"
  #
  # Conservative - when in doubt keep tokens; over-stripping merges distinct
  # merchants.
  class TitleNormalizer
    # Add cities as they appear; over-broad regex would eat real merchant
    # tokens (e.g. "POZ" inside a longer name).
    KNOWN_CITY_PREFIXES = %w[
      RZESZOW WARSZAWA KRAKOW KRAKOW POZNAN WROCLAW GDANSK GDYNIA SZCZECIN
      LODZ LUBLIN BYDGOSZCZ BIALYSTOK KATOWICE SOSNOWIEC ZLOTOW TORUN
    ].freeze

    CITY_PREFIX_RE = /\A(#{KNOWN_CITY_PREFIXES.join('|')})/i

    def self.call(title) = new(title).call

    # Conservative, dot-preserving variant - keeps casing and punctuation
    # so the result is still a valid `contains` pattern against the original
    # title. Used as a fallback when the LLM proposes a non-matching pattern.
    def self.likely_pattern(title)
      return nil if title.blank?
      result = title.to_s
      result = result.sub(CITY_PREFIX_RE, "")
      result = result.sub(/PL\z/, "")
      result = result.gsub(/\d+/, " ")
      tokens = result.split(/\s+/).reject(&:empty?).select { |t| t.length >= 3 }
      tokens.max_by(&:length)
    end

    def initialize(title)
      @title = title.to_s
    end

    def call
      return "" if @title.blank?

      result = @title.upcase
      result = result.sub(CITY_PREFIX_RE, "")
      result = result.sub(/PL\z/, "")
      result = result.gsub(/\d+/, " ")
      result = result.gsub(/[^\p{L}\s.&-]/u, " ")
      result = result.tr(".", " ")
      result.squeeze(" ").strip
    end
  end
end
