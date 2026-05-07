# frozen_string_literal: true

module Categories
  # ltree has no native "rename ancestor" - when `parent_path` changes, the
  # category's path is recomposed AND every descendant's path is rewritten
  # in a single UPDATE inside a transaction (a partial move would leave the
  # tree unreachable).
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
        # Skip the path assignment when the candidate isn't ltree-compatible.
        # The model's slug format validator surfaces the real error - leaving
        # path untouched also keeps the persisted in-memory value valid for
        # the edit form's `self_and_descendants` lookup on re-render.
        candidate = compose_path(@parent_path, attrs[:slug] || @category.slug)
        attrs[:path] = candidate if candidate.match?(::Category::LTREE_PATH_FORMAT)
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

    # `subpath(path, nlevel(old_path))` strips the old prefix; the new prefix
    # is concatenated via `||`. One UPDATE for the whole subtree.
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
