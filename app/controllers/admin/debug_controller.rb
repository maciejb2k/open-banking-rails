# frozen_string_literal: true

module Admin
  class DebugController < BaseController
    def index
    end

    def runtime_error
      raise RuntimeError, "Test RuntimeError from admin debug endpoint"
    end

    def zero_division
      1 / 0
    end

    def argument_error
      Integer("not_a_number")
    end

    def nested_error
      begin
        raise RuntimeError, "original cause"
      rescue RuntimeError
        raise StandardError, "wrapping error with cause"
      end
    end

    def enqueue_failing_job
      FailingJob.perform_later(error_type: params[:error_type] || "runtime")
      head :no_content
    end
  end
end
