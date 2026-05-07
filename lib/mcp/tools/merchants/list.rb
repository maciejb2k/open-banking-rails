# frozen_string_literal: true

module Mcp
  module Tools
    module Merchants
      class List < Mcp::ApplicationTool
        tool_name "merchants.list"
        description "List the user's merchants. Default: active only, name ASC, max 100 rows."

        input_schema(
          properties: {
            q:                { type: "string", description: "Name ILIKE %q%" },
            source:           { type: "string", enum: %w[user llm seed system] },
            category_id:      { type: "integer" },
            include_archived: { type: "boolean" },
            limit:            { type: "integer", description: "1-200, default 50" }
          }
        )

        def self.call(server_context:, **args)
          user  = current_user(server_context)
          limit = [ [ args[:limit].to_i, 1 ].max, 200 ].min
          limit = 50 if limit.zero?

          scope = user.merchants
          scope = scope.active unless args[:include_archived]
          scope = scope.where(source: args[:source]) if args[:source]
          scope = scope.where(default_category_id: args[:category_id]) if args[:category_id]
          scope = scope.where("name ILIKE ?", "%#{args[:q]}%") if args[:q].present?

          rows = scope.includes(:default_category).order(:name).limit(limit).map do |m|
            { id: m.id, name: m.name, slug: m.slug, kind: m.kind, source: m.source,
              default_category_id: m.default_category_id,
              default_category_path: m.default_category&.path&.to_s,
              archived_at: m.archived_at, approved_at: m.approved_at }
          end
          json(count: rows.size, merchants: rows)
        end
      end
    end
  end
end
