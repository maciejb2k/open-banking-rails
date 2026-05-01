# frozen_string_literal: true

module Enrichment
  # Pure function: collapse the bank-supplied transaction title into a stable
  # key for grouping. Two transactions at the same merchant should normalize
  # to the same string, so the LLM in Phase 3 is asked once per merchant
  # instead of once per transaction.
  #
  # mBank format observed in the wild:
  #   RZESZOWLIDL 01PL                  → "LIDL"
  #   RZESZOWJMP S.A. BIEDRONKA 7645PL  → "JMP S.A. BIEDRONKA"
  #   RzeszoweLeclercPL                 → "LECLERC"
  #   POZNANAllegroPayPL                → "ALLEGROPAY"
  #
  # Strategy: uppercase, strip leading city prefix, strip trailing PL,
  # remove digits and noise punctuation, collapse whitespace. Conservative
  # — when in doubt we keep tokens, since over-stripping would merge
  # distinct merchants.
  class TitleNormalizer
    # Polish city names that mBank prepends to card-payment titles.
    # Add new ones as they appear; over-broad regex would eat real merchant
    # tokens (e.g. "POZ" inside a longer name).
    KNOWN_CITY_PREFIXES = %w[
      RZESZOW WARSZAWA KRAKOW KRAKOW POZNAN WROCLAW GDANSK GDYNIA SZCZECIN
      LODZ LUBLIN BYDGOSZCZ BIALYSTOK KATOWICE SOSNOWIEC ZLOTOW TORUN
    ].freeze

    CITY_PREFIX_RE = /\A(#{KNOWN_CITY_PREFIXES.join('|')})/i

    def self.call(title) = new(title).call

    # Conservative, dot-preserving variant — keeps casing and punctuation
    # (except city / trailing PL / digits) so the result is still a valid
    # `contains` pattern against the original title:
    #
    #   "RzeszowP.U.N.K.TPL"  → "P.U.N.K.T"
    #   "RZESZOWLIDL 01PL"    → "LIDL"
    #   "RzeszowAl CaponePL"  → "Al Capone"
    #
    # Used as a fallback pattern when the LLM proposes one that doesn't
    # match the source title (see EnrichmentRunner#enforce_pattern_matches).
    # Returns the longest meaningful token (>= 3 chars) — covers single-
    # name (LIDL), multi-word (AL CAPONE), and dotted (P.U.N.K.T) cases.
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
      result = result.sub(CITY_PREFIX_RE, "")        # strip city prefix
      result = result.sub(/PL\z/, "")                # strip trailing country
      result = result.gsub(/\d+/, " ")               # location codes / store numbers
      result = result.gsub(/[^\p{L}\s.&-]/u, " ")    # keep letters, dots, &, dashes
      result = result.tr(".", " ")                   # then drop the dots
      result.squeeze(" ").strip
    end
  end
end
