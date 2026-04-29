# frozen_string_literal: true

module Admin
  class CategoriesController < BaseController
    before_action :set_category, only: %i[edit update destroy archive unarchive]

    def index
      @top_level = Category.top_level.active.includes(:children).order(Arel.sql("LOWER(name) ASC"))
      @archived  = Category.archived.includes(:parent).order(Arel.sql("LOWER(name) ASC"))
    end

    def new
      @category = Category.new(parent_id: params[:parent_id], kind: "expense")
    end

    def create
      @category = Category.new(category_params)
      @category.slug ||= generate_slug(@category.name)
      if @category.save
        redirect_to admin_categories_path, notice: "Category created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @category.update(category_params)
        redirect_to admin_categories_path, notice: "Category updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Hard delete only when nothing depends on it; otherwise direct user
    # to archive instead.
    def destroy
      if @category.children.any? || @category.merchants.any? || @category.transaction_enrichments.any?
        redirect_to admin_categories_path,
                    alert: "Can't delete — this category is in use. Archive it instead."
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
      @category = Category.find(params[:id])
    end

    def category_params
      params.expect(category: %i[name slug parent_id kind color icon position])
    end

    # Best-effort slug from name; user can override the generated value.
    # Existing slug is never replaced — slugs are stable identifiers.
    def generate_slug(name)
      return nil if name.blank?
      base = name.to_s.downcase.gsub(/\p{M}/, "").gsub(/[^a-z0-9]+/, "_").gsub(/_+/, "_").gsub(/\A_|_\z/, "")
      candidate = base
      i = 2
      while Category.exists?(slug: candidate)
        candidate = "#{base}_#{i}"
        i += 1
      end
      candidate
    end
  end
end
