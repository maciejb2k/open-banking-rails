# frozen_string_literal: true

module EnableBanking
  module Operations
    # Convention for operation services:
    #   EnableBanking::Operations::SomeOperation.call(**args) → domain object
    #
    # Operations encapsulate a single business action that combines one or
    # more API calls (EnableBanking::Api::*) with persistence/state changes.
    # They raise `Operation::Failed` (or subclasses) on unhappy paths so
    # controllers can keep the rescue→redirect pattern thin.
    class Base
      # Default Failed — subclasses define their own (Failed = Class.new(StandardError))
      # so callers can rescue per-operation. Base#call wires `self::Failed` so
      # whichever Failed the subclass defines is what gets raised on
      # EnableBanking::Error config failures.
      Failed = Class.new(StandardError)

      def self.call(*args, **kwargs)
        instance = kwargs.empty? ? new(*args) : new(*args, **kwargs)
        instance.call
      rescue EnableBanking::Error => e
        raise self::Failed, "Configuration error: #{e.message}"
      end
    end
  end
end
