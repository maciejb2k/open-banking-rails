# frozen_string_literal: true

module AutoSync
  # Creates or updates the SyncSchedule for a BankConnection from form input.
  # Recomputes next_run_at when the user changes timing (cadence/hour) or
  # transitions disabled→enabled — otherwise leaves it alone so toggling off
  # and on without other edits resumes from the previously-planned slot.
  class ScheduleUpserter
    Input = Struct.new(:enabled, :cadence, :preferred_hour, keyword_init: true) do
      def parsed_enabled = ActiveModel::Type::Boolean.new.cast(enabled)
      def parsed_cadence = cadence.to_s.strip.presence
      def parsed_hour
        Integer(preferred_hour)
      rescue ArgumentError, TypeError
        nil
      end
    end

    Result = Struct.new(:success?, :schedule, :error_messages, keyword_init: true) do
      def error = Array(error_messages).join(", ")
    end

    def self.call(...) = new(...).call

    def initialize(connection:, user:, input:)
      @connection = connection
      @user = user
      @input = input
    end

    def call
      schedule = SyncSchedule.find_or_initialize_by(bank_connection: @connection)
      previous = snapshot(schedule)

      schedule.assign_attributes(assigned_attrs(schedule))
      schedule.next_run_at = recomputed_next_run(schedule) if recompute_needed?(schedule, previous)

      schedule.save!
      Result.new(success?: true, schedule: schedule)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, schedule: e.record, error_messages: e.record.errors.full_messages)
    end

    private

    def assigned_attrs(schedule)
      {
        enabled: @input.parsed_enabled,
        cadence: @input.parsed_cadence || schedule.cadence,
        preferred_hour: @input.parsed_hour || schedule.preferred_hour
      }
    end

    def snapshot(schedule)
      { enabled: schedule.enabled, cadence: schedule.cadence, preferred_hour: schedule.preferred_hour }
    end

    # Recompute when: scheduling on for the first time, transitioning off→on,
    # or user changed timing while on. Disabling never recomputes.
    def recompute_needed?(schedule, prev)
      return false unless schedule.enabled
      schedule.next_run_at.nil? ||
        prev[:enabled] == false ||
        prev[:cadence] != schedule.cadence ||
        prev[:preferred_hour] != schedule.preferred_hour
    end

    # Pass the schedule's last_dispatched_at so a cadence change on a long-
    # running schedule honors the new interval (daily → weekly waits a week,
    # not until tomorrow). For never-dispatched schedules, nil → first-fire
    # semantics: next preferred-hour slot ASAP.
    def recomputed_next_run(schedule)
      NextRunCalculator.call(
        input: NextRunCalculator::Input.new(
          cadence: schedule.cadence,
          preferred_hour: schedule.preferred_hour,
          timezone: user_timezone,
          from: Time.current
        ),
        last_dispatched_at: schedule.last_dispatched_at
      )
    end

    def user_timezone
      @user.respond_to?(:timezone) ? (@user.timezone.presence || "UTC") : "UTC"
    end
  end
end
