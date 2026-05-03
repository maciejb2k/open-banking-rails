# frozen_string_literal: true

# Per-connection (not per-user) because rate limits are per-bank - a user
# with mBank + Revolut may want different cadences. Slot computation lives
# in AutoSync::NextRunCalculator.
class SyncSchedule < ApplicationRecord
  CADENCES = %w[daily every_2_days weekly].freeze

  # Consecutive failures before the circuit breaker pauses the schedule.
  FAILURE_THRESHOLD = 3

  belongs_to :bank_connection

  validates :cadence,        presence: true, inclusion: { in: CADENCES }
  validates :preferred_hour, presence: true,
                             numericality: { only_integer: true, in: 0..23 }
  validates :consecutive_failures, numericality: { only_integer: true,
                                                   greater_than_or_equal_to: 0 }

  # next_run_at NULL means "never computed" - also due.
  scope :due, -> {
    now = Time.current
    where(enabled: true)
      .where("next_run_at IS NULL OR next_run_at <= ?", now)
      .where("paused_until IS NULL OR paused_until <= ?", now)
  }

  def paused?
    paused_until.present? && paused_until > Time.current
  end
end
