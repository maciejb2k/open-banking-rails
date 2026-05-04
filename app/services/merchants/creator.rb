# frozen_string_literal: true

module Merchants
  class Creator
    Result = Struct.new(:success?, :merchant, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(user:, attributes:)
      @user       = user
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      merchant = @user.merchants.new(@attributes.merge(
        source:      "user",
        approved_at: Time.current,
        approved_by: @user
      ))
      merchant.slug = generate_slug(merchant.name) if merchant.slug.blank?

      if merchant.save
        Result.new(success?: true, merchant: merchant)
      else
        Result.new(success?: false, merchant: merchant, error_messages: merchant.errors.full_messages)
      end
    end

    private

    def generate_slug(name)
      base = name.to_s.downcase.gsub(/\p{M}/, "").gsub(/[^a-z0-9]+/, "_").gsub(/_+/, "_").gsub(/\A_|_\z/, "")
      candidate = base
      i = 2
      while @user.merchants.exists?(slug: candidate)
        candidate = "#{base}_#{i}"
        i += 1
      end
      candidate
    end
  end
end
