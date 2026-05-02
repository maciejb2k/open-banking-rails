# frozen_string_literal: true

# Per-BankConnection auto-sync configuration. The dispatcher
# (AutoSync::Dispatcher) scans `due` once per minute, creates a scheduled
# OperationRun for each, and advances next_run_at via NextRunCalculator.
#
# Per-connection (not per-user) because rate limits are per-bank: a user
# with mBank + Revolut may want different cadences. Slot computation
# lives in AutoSync::NextRunCalculator — keep it out of the model.
class SyncSchedule < ApplicationRecord
  CADENCES = %w[daily every_2_days weekly].freeze

  # Threshold for the circuit breaker. After this many consecutive
  # failed/partial runs, AutoSync::CircuitBreaker (slice 3) sets
  # paused_until and bumps it back into `due` only after the cooldown.
  FAILURE_THRESHOLD = 3

  belongs_to :bank_connection

  validates :cadence,        presence: true, inclusion: { in: CADENCES }
  validates :preferred_hour, presence: true,
                             numericality: { only_integer: true, in: 0..23 }
  validates :consecutive_failures, numericality: { only_integer: true,
                                                   greater_than_or_equal_to: 0 }

  # Schedules the dispatcher should pick up this tick:
  # - enabled by the user
  # - next_run_at has elapsed (NULL means "never computed" — also due)
  # - not currently paused by the circuit breaker
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
