# frozen_string_literal: true

module Mcp
  module Tools
    module Categories
      class Archive < Mcp::ApplicationTool
        tool_name "categories.archive"
        description "Archive a category - kept in storage but hidden from active lists."

        input_schema(properties: { id: { type: "integer" } }, required: %w[id])

        def self.call(server_context:, **args)
          user = current_user(server_context)
          category = user.categories.find_by(id: args[:id])
          return error("Category ##{args[:id]} not found.") unless category

          category.archive!
          text("Archived category '#{category.name}'.")
        end
      end
    end
  end
end
