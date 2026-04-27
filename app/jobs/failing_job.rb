# frozen_string_literal: true

class FailingJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 3.seconds, attempts: 3

  def perform(error_type: "runtime")
    case error_type
    when "runtime"
      raise RuntimeError, "FailingJob: intentional RuntimeError"
    when "argument"
      raise ArgumentError, "FailingJob: intentional ArgumentError"
    when "zero_division"
      1 / 0
    end
  end
end
