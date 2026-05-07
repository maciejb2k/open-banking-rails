# frozen_string_literal: true

# Thin wrappers over ActiveSupport::Testing::TimeHelpers. Time-sensitive
# specs freeze in BUSINESS_TZ rather than UTC to catch DST and midnight
# regressions in auto-sync, recurrence, and scheduling code.
module TimeHelpers
  BUSINESS_TZ = "Europe/Warsaw"

  def freeze_at(time, &block)
    travel_to(time, &block)
  end

  def advance(duration)
    travel(duration)
  end

  def in_business_tz(&block)
    Time.use_zone(BUSINESS_TZ, &block)
  end
end
