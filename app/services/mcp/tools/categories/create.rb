# frozen_string_literal: true

module Mcp
  module Tools
    module Categories
      class Create < Mcp::ApplicationTool
        tool_name "categories.create"
        description "Create a new category. parent_path is the ltree path of the parent ('food.cooking' etc.); omit for top-level."

        input_schema(
          properties: {
            name:        { type: "string" },
            slug:        { type: "string", description: "Auto-generated when omitted" },
            kind:        { type: "string", enum: %w[expense income transfer savings ignored] },
            color:       { type: "string" },
            icon:        { type: "string" },
            position:    { type: "integer" },
            essential:   { type: "boolean" },
            parent_path: { type: "string" }
          },
          required: %w[name]
        )

        def self.call(server_context:, **args)
          user   = current_user(server_context)
          attrs  = args.symbolize_keys
          result = ::Categories::Creator.call(
            user:        user,
            attributes:  attrs.except(:parent_path),
            parent_path: attrs[:parent_path]
          )
          from_result(result, on_success: ->(r) {
            json(id: r.category.id, name: r.category.name, slug: r.category.slug,
                 path: r.category.path.to_s, kind: r.category.kind)
          })
        end
      end
    end
  end
end
