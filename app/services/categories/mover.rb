# frozen_string_literal: true

module Categories
  # Updates a Category in place. The interesting case is when its position
  # in the tree changes — `parent_path` was passed and resolves to a
  # different ancestor. In that case the category's `path` is recomposed
  # AND every descendant's path has its prefix rewritten in a single
  # SQL UPDATE so the subtree stays consistent.
  #
  # ltree has no native "rename ancestor" operation; the rewrite uses
  # `subpath(...)` to splice in the new prefix. Wrapped in a transaction
  # so the parent move and the descendant rewrite either both happen or
  # neither does — a partial move would leave the tree in an
  # unreachable state.
  #
  # Plain attribute updates (name, color, kind, …) flow through here too;
  # this service is the single update entry point for categories.
  class Mover
    Result = Struct.new(:success?, :category, :error_messages, keyword_init: true) do
      def error
        Array(error_messages).join(", ")
      end
    end

    def self.call(...) = new(...).call

    def initialize(category:, attributes:, parent_path: nil)
      @category    = category
      @attributes  = attributes
      @parent_path = parent_path
    end

    def call
      attrs = @attributes.dup
      if @parent_path.present?
        attrs[:path] = compose_path(@parent_path, attrs[:slug] || @category.slug)
      end

      ActiveRecord::Base.transaction do
        if @category.update(attrs)
          if @parent_path.present? && @category.saved_change_to_path?
            rewrite_descendant_paths(@category.path_before_last_save, @category.path)
          end
          Result.new(success?: true, category: @category)
        else
          Result.new(success?: false, category: @category, error_messages: @category.errors.full_messages)
        end
      end
    end

    private

    def compose_path(parent_path, slug)
      return slug.to_s if parent_path.blank?
      "#{parent_path}.#{slug}"
    end

    # Rewrite every descendant's path so its prefix matches the new
    # ancestor's path. `subpath(path, nlevel(old_path))` strips the old
    # prefix; the new prefix is concatenated via the `||` ltree operator.
    # One UPDATE for the whole subtree.
    def rewrite_descendant_paths(old_path, new_path)
      @category.user.categories
                    .where("path <@ ? AND path != ?", old_path, old_path)
                    .update_all([
                      "path = ?::ltree || subpath(path, nlevel(?::ltree))",
                      new_path, old_path
                    ])
    end
  end
end
