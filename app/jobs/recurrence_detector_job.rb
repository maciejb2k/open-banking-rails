# frozen_string_literal: true

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
