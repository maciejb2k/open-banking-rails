# frozen_string_literal: true

module Mcp
  module Tools
    module Categories
      class Unarchive < Mcp::ApplicationTool
        tool_name "categories.unarchive"
        description "Restore a previously archived category."

        input_schema(properties: { id: { type: "integer" } }, required: %w[id])

        def self.call(server_context:, **args)
          user = current_user(server_context)
          category = user.categories.find_by(id: args[:id])
          return error("Category ##{args[:id]} not found.") unless category

          category.unarchive!
          text("Restored category '#{category.name}'.")
        end
      end
    end
  end
end
