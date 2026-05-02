# frozen_string_literal: true

module AutoSync
  # Computes the next dispatch time for a SyncSchedule.
  #
  # Two modes, controlled by `last_dispatched_at`:
  #
  # - First-fire (last_dispatched_at = nil): baseline is `from` (now). Used
  #   when the user just enables a fresh schedule — fire at the next
  #   preferred-hour slot, ASAP.
  #
  # - Recurring (last_dispatched_at present): baseline is
  #   max(from, last_dispatched_at + interval). Keeps cadence honest even
  #   after long downtime — `max` snaps the baseline forward to "now" so we
  #   don't fire a backlog of missed runs (fire-once-on-recovery).
  #
  # The baseline is then snapped UP to the next preferred-hour slot, plus
  # random jitter (default 0..300s) so popular hours like 08:00 don't
  # thunder-herd the bank APIs.
  class NextRunCalculator
    DEFAULT_JITTER_SECONDS = 0..300

    # Cadence → time gap between successive fires. Adding a new entry here
    # is the only change required to support a new cadence (plus updating
    # SyncSchedule::CADENCES for validation).
    INTERVALS = {
      "daily"        => 1.day,
      "every_2_days" => 2.days,
      "weekly"       => 7.days
    }.freeze

    Input = Struct.new(:cadence, :preferred_hour, :timezone, :from, :jitter, keyword_init: true) do
      def zone
        ActiveSupport::TimeZone.new(timezone || "UTC") || ActiveSupport::TimeZone.new("UTC")
      end

      def from_time
        (from || Time.current).in_time_zone(zone)
      end

      def jitter_range
        jitter || DEFAULT_JITTER_SECONDS
      end
    end

    def self.call(...) = new(...).call

    def initialize(input:, last_dispatched_at: nil)
      @input = input
      @last_dispatched_at = last_dispatched_at
    end

    def call
      snap_to_preferred_hour(baseline) + rand(@input.jitter_range).seconds
    end

    private

    def baseline
      return @input.from_time if @last_dispatched_at.nil?
      candidate = @last_dispatched_at.in_time_zone(@input.zone) + interval
      [@input.from_time, candidate].max
    end

    def snap_to_preferred_hour(time)
      slot = time.change(hour: @input.preferred_hour, min: 0, sec: 0)
      slot >= time ? slot : slot + 1.day
    end

    def interval
      INTERVALS.fetch(@input.cadence) { raise ArgumentError, "Unknown cadence: #{@input.cadence.inspect}" }
    end
  end
end
