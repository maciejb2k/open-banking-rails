# frozen_string_literal: true

module Admin
  class CategoriesController < BaseController
    before_action :set_category, only: %i[edit update destroy archive unarchive]

    def index
      @categories = current_user.categories.active.ordered.to_a
      @archived   = current_user.categories.archived.ordered
    end

    def new
      @category = current_user.categories.new(kind: "expense")
      @parent_path = params[:parent_path]
    end

    def create
      result = Categories::Creator.call(
        user:        current_user,
        attributes:  category_params.except(:parent_path),
        parent_path: params.dig(:category, :parent_path)
      )

      if result.success?
        redirect_to admin_categories_path, notice: "Category created."
      else
        @category    = result.category
        @parent_path = params.dig(:category, :parent_path)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      return unless current_user.hides_category?(@category)

      redirect_to admin_categories_path,
                  alert: "This category is private. Remove it from the hidden list in preferences to edit it."
    end

    def update
      result = Categories::Mover.call(
        category:    @category,
        attributes:  category_params.except(:parent_path),
        parent_path: params.dig(:category, :parent_path)
      )

      if result.success?
        redirect_to admin_categories_path, notice: "Category updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @category.descendants.any? || @category.merchants.any? || @category.transaction_enrichments.any?
        redirect_to admin_categories_path,
                    alert: "Can't delete - this category is in use or has sub-categories. Archive it instead."
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
  end
end
