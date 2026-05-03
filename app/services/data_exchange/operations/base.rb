# frozen_string_literal: true

module DataExchange
  module Operations
    class Base
      Failed = Class.new(StandardError)

      def self.call(*args, **kwargs)
        instance = kwargs.empty? ? new(*args) : new(*args, **kwargs)
        instance.call
      end
    end
  end
end
