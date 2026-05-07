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
FactoryBot.define do
  factory :sync_schedule do
    bank_connection { association :bank_connection, :active }
    enabled         { true }
    cadence         { "daily" }
    preferred_hour  { 8 }
    next_run_at     { 1.day.from_now }

    trait :active do
      enabled { true }
    end

    trait :paused do
      enabled       { false }
      paused_until  { 1.day.from_now }
    end

    trait :hourly do
      cadence { "daily" }
    end

    trait :daily do
      cadence { "daily" }
    end
  end
end
