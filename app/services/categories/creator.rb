# frozen_string_literal: true

module Categories
  class Creator
    Result = Struct.new(:success?, :category, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(user:, attributes:, parent_path: nil)
      @user        = user
      @attributes  = attributes
      @parent_path = parent_path
    end

    def call
      category = @user.categories.new(@attributes)
      category.slug ||= generate_slug(category.name)
      category.path   = compose_path(@parent_path, category.slug)

      if category.save
        Result.new(success?: true, category: category)
      else
        Result.new(success?: false, category: category, error_messages: category.errors.full_messages)
      end
    end

    private

    def compose_path(parent_path, slug)
      return slug.to_s if parent_path.blank?
      "#{parent_path}.#{slug}"
    end

    def generate_slug(name)
      return nil if name.blank?
      base = name.to_s.downcase
                  .gsub(/\p{M}/, "")
                  .gsub(/[^a-z0-9]+/, "_")
                  .gsub(/_+/, "_")
                  .gsub(/\A_|_\z/, "")
      candidate = base
      i = 2
      while @user.categories.exists?(slug: candidate)
        candidate = "#{base}_#{i}"
        i += 1
      end
      candidate
    end
  end
end
