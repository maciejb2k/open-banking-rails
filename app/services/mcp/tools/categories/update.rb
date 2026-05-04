# frozen_string_literal: true

module Mcp
  module Tools
    module Categories
      class Update < Mcp::ApplicationTool
        tool_name "categories.update"
        description "Update / move a category. Changing parent_path rewrites paths of all descendants atomically."

        input_schema(
          properties: {
            id:          { type: "integer" },
            name:        { type: "string" },
            slug:        { type: "string" },
            kind:        { type: "string", enum: %w[expense income transfer savings ignored] },
            color:       { type: "string" },
            icon:        { type: "string" },
            position:    { type: "integer" },
            essential:   { type: "boolean" },
            parent_path: { type: "string" }
          },
          required: %w[id]
        )

        def self.call(server_context:, **args)
          user     = current_user(server_context)
          category = user.categories.find_by(id: args[:id])
          return error("Category ##{args[:id]} not found.") unless category

          attrs  = args.symbolize_keys.except(:id)
          result = ::Categories::Mover.call(
            category:    category,
            attributes:  attrs.except(:parent_path),
            parent_path: attrs[:parent_path]
          )
          from_result(result, on_success: ->(r) {
            json(id: r.category.id, name: r.category.name, path: r.category.path.to_s)
          })
        end
      end
    end
  end
end
