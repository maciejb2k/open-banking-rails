# frozen_string_literal: true

module EnableBanking
  module Operations
    class Base
      # Subclasses redefine Failed so callers can rescue per-operation.
      # Base#call wires `self::Failed` so the subclass's Failed is what
      # actually gets raised on EnableBanking::Error config failures.
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
