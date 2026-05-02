# frozen_string_literal: true

module DataExchange
  module Operations
    # Convention mirrors EnableBanking::Operations::Base — operations expose
    # `.call(**args)` and raise `self::Failed` on unhappy paths so controllers
    # keep a thin rescue→redirect.
    class Base
      Failed = Class.new(StandardError)

      def self.call(*args, **kwargs)
        instance = kwargs.empty? ? new(*args) : new(*args, **kwargs)
        instance.call
      end
    end
  end
end
