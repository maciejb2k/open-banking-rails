# frozen_string_literal: true

# == Schema Information
#
# Table name: sync_schedules
#
#  id                   :bigint           not null, primary key
#  cadence              :string           default("daily"), not null
#  consecutive_failures :integer          default(0), not null
#  enabled              :boolean          default(FALSE), not null
#  last_dispatched_at   :datetime
#  next_run_at          :datetime
#  paused_until         :datetime
#  preferred_hour       :integer          default(8), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  bank_connection_id   :bigint           not null
#
# Indexes
#
#  index_sync_schedules_due                    (enabled,next_run_at) WHERE (enabled = true)
#  index_sync_schedules_on_bank_connection_id  (bank_connection_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (bank_connection_id => bank_connections.id)
#
class SyncSchedule < ApplicationRecord
  # Per-connection (not per-user) because rate limits are per-bank - a user
  # with mBank + Revolut may want different cadences. Slot computation lives
  # in AutoSync::NextRunCalculator.
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
