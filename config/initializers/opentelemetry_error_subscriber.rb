# frozen_string_literal: true

class OpenTelemetryErrorSubscriber
  def report(error, handled:, severity:, context: {}, source: nil)
    span = OpenTelemetry::Trace.current_span
    return unless span.recording?

    span.record_exception(error)
    span.status = OpenTelemetry::Trace::Status.error(error.message)
  end
end

Rails.error.subscribe(OpenTelemetryErrorSubscriber.new)
