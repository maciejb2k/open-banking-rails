# frozen_string_literal: true

# Nightly job: re-detect recurring charges per user and write the Layer 2
# flag onto enrichments. Idempotent — running multiple times the same day
# is a no-op when nothing changed.
class RecurrenceDetectorJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil)
    if user_id
      Recurrence::Detector.call(user: User.find(user_id))
    else
      User.find_each { |u| Recurrence::Detector.call(user: u) }
    end
  end
end
