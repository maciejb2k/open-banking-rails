# frozen_string_literal: true

module Resources
  class Categories < Grape::API
    before { authenticate! }

    resource :categories do
      desc "List categories" do
        success model: Entities::Category, is_array: true
      end
      params do
        optional :include_archived, type: Boolean, default: false
      end
      get do
        scope = current_user.categories
        scope = params[:include_archived] ? scope : scope.active
        present scope.ordered, with: Entities::Category
      end

      desc "Create a category" do
        success model: Entities::Category
        failure [ [ 422, "Validation error" ] ]
      end
      params do
        requires :name,        type: String
        optional :slug,        type: String
        optional :kind,        type: String, values: %w[expense income transfer savings ignored], default: "expense"
        optional :color,       type: String
        optional :icon,        type: String
        optional :position,    type: Integer
        optional :essential,   type: Boolean
        optional :parent_path, type: String, desc: "Parent ltree path; null/empty = top-level"
      end
      post do
        attrs = declared(params, include_missing: false).symbolize_keys
        result = ::Categories::Creator.call(
          user:        current_user,
          attributes:  attrs.except(:parent_path),
          parent_path: attrs[:parent_path]
        )
        if result.success?
          status 201
          present result.category, with: Entities::Category
        else
          error!({ message: result.error, details: Array(result.error_messages) }, 422)
        end
      end

      route_param :id, type: Integer do
        helpers do
          def load_category!
            current_user.categories.find(params[:id])
          end
        end

        desc "Fetch a category" do
          success model: Entities::Category
        end
        get do
          present load_category!, with: Entities::Category
        end

        desc "Update / move a category" do
          success model: Entities::Category
        end
        params do
          optional :name,        type: String
          optional :slug,        type: String
          optional :kind,        type: String, values: %w[expense income transfer savings ignored]
          optional :color,       type: String
          optional :icon,        type: String
          optional :position,    type: Integer
          optional :essential,   type: Boolean
          optional :parent_path, type: String
        end
        patch do
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = ::Categories::Mover.call(
            category:    load_category!,
            attributes:  attrs.except(:parent_path),
            parent_path: attrs[:parent_path]
          )
          if result.success?
            present result.category, with: Entities::Category
          else
            error!({ message: result.error, details: Array(result.error_messages) }, 422)
          end
        end

        desc "Delete a category (only when unused)"
        delete do
          category = load_category!
          if category.in_use?
            error!({ message: "Can't delete - this category is in use or has sub-categories. Archive it instead." }, 422)
          end
          category.destroy!
          status 204
          ""
        end

        desc "Archive a category" do
          success model: Entities::Category
        end
        post :archive do
          category = load_category!
          category.archive!
          present category, with: Entities::Category
        end

        desc "Unarchive a category" do
          success model: Entities::Category
        end
        post :unarchive do
          category = load_category!
          category.unarchive!
          present category, with: Entities::Category
        end
      end
    end
  end
end
