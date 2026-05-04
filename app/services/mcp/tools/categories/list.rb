# frozen_string_literal: true

module Mcp
  module Tools
    module Categories
      class List < Mcp::ApplicationTool
        tool_name "categories.list"
        description "List the user's categories. Hierarchy is encoded in `path` (ltree dot-separated)."

        input_schema(
          properties: {
            include_archived: { type: "boolean", description: "Default false" }
          }
        )

        def self.call(server_context:, **args)
          user  = current_user(server_context)
          scope = args[:include_archived] ? user.categories : user.categories.active

          rows = scope.ordered.map do |c|
            { id: c.id, name: c.name, slug: c.slug, path: c.path.to_s,
              kind: c.kind, essential: c.essential, archived_at: c.archived_at }
          end
          json(count: rows.size, categories: rows)
        end
      end
    end
  end
end
