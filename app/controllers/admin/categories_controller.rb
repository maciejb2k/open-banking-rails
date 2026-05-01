# frozen_string_literal: true

module Admin
  class CategoriesController < BaseController
    before_action :set_category, only: %i[edit update destroy archive unarchive]

    # Render every category in path order — the natural left-right
    # traversal of the tree. Indentation in the view is depth-based.
    def index
      @categories = current_user.categories.active.ordered.to_a
      @archived   = current_user.categories.archived.ordered
    end

    def new
      @category = current_user.categories.new(kind: "expense")
      @parent_path = params[:parent_path]
    end

    def create
      @category = current_user.categories.new(category_params.except(:parent_path))
      @category.slug ||= generate_slug(@category.name)
      @category.path   = compose_path(params.dig(:category, :parent_path), @category.slug)
      if @category.save
        redirect_to admin_categories_path, notice: "Category created."
      else
        @parent_path = params.dig(:category, :parent_path)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      # Editing a hidden category exposes its name in the form header +
      # the form fields. Bounce; user has to remove from the hidden list
      # in /admin/settings/preferences to inspect.
      if current_user.hides_category?(@category)
        redirect_to admin_categories_path,
                    alert: "This category is private. Remove it from the hidden list in preferences to edit it."
        return
      end
    end

    def update
      attrs = category_params.except(:parent_path)
      new_parent_path = params.dig(:category, :parent_path)
      attrs[:path] = compose_path(new_parent_path, attrs[:slug] || @category.slug) if new_parent_path

      if @category.update(attrs)
        # If the path changed, every descendant's path is now stale —
        # they still have the old prefix. Rewrite the subtree in one
        # SQL update per ancestor swap.
        if new_parent_path && @category.saved_change_to_path?
          rewrite_descendant_paths(@category.path_before_last_save, @category.path)
        end
        redirect_to admin_categories_path, notice: "Category updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Hard delete only when nothing depends on it; otherwise direct user
    # to archive instead. Subtree-aware — a category with descendants
    # can't go away without orphaning them.
    def destroy
      if @category.descendants.any? || @category.merchants.any? || @category.transaction_enrichments.any?
        redirect_to admin_categories_path,
                    alert: "Can't delete — this category is in use or has sub-categories. Archive it instead."
      else
        @category.destroy
        redirect_to admin_categories_path, notice: "Category deleted."
      end
    end

    def archive
      @category.archive!
      redirect_to admin_categories_path, notice: "Category archived."
    end

    def unarchive
      @category.unarchive!
      redirect_to admin_categories_path, notice: "Category restored."
    end

    private

    def set_category
      @category = current_user.categories.find(params[:id])
    end

    def category_params
      params.expect(category: %i[name slug parent_path kind color icon position essential])
    end

    # Compose the full ltree path from (parent_path, slug). Empty parent
    # path means the new category is a top-level domain.
    def compose_path(parent_path, slug)
      return slug.to_s if parent_path.blank?
      "#{parent_path}.#{slug}"
    end

    # When a category is moved (path changes), every descendant must be
    # rewritten so their paths still start with the new ancestor. ltree
    # has no native "rename ancestor" — we do it in one UPDATE.
    def rewrite_descendant_paths(old_path, new_path)
      current_user.categories.where("path <@ ? AND path != ?", old_path, old_path)
        .update_all(["path = ?::ltree || subpath(path, nlevel(?::ltree))", new_path, old_path])
    end

    # Best-effort slug from name; user can override the generated value.
    # Existing slug is never replaced — slugs are stable identifiers.
    def generate_slug(name)
      return nil if name.blank?
      base = name.to_s.downcase.gsub(/\p{M}/, "").gsub(/[^a-z0-9]+/, "_").gsub(/_+/, "_").gsub(/\A_|_\z/, "")
      candidate = base
      i = 2
      while current_user.categories.exists?(slug: candidate)
        candidate = "#{base}_#{i}"
        i += 1
      end
      candidate
    end
  end
end
