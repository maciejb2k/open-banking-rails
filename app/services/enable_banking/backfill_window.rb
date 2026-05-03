# frozen_string_literal: true

module EnableBanking
  # Banks silently truncate beyond their cap - no error, just missing data.
  module BackfillWindow
    HORIZONS = {
      "revolut"         => 90,    # PSD2 hard 90-day cap, strictly enforced
      "pko_bank_polski" => 26 * 30, # ~26 months
      "mbank"           => 90    # bank caps to 90d despite EB advertising 180
    }.freeze

    DEFAULT_DAYS = 90

    def self.days_for(bank_slug)
      HORIZONS.fetch(bank_slug, DEFAULT_DAYS)
    end

    def self.default_date_from(bank_slug, today: Date.current)
      today - days_for(bank_slug)
    end
  end
end
