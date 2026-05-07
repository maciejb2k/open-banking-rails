# frozen_string_literal: true

module Entities
  class Category < Grape::Entity
    expose :id,        documentation: { type: Integer }
    expose :name,      documentation: { type: String }
    expose :slug,      documentation: { type: String }
    expose :path,      documentation: { type: String, desc: "Materialized ltree path" } do |c|
      c.path.to_s
    end
    expose :kind,      documentation: { type: String, desc: "expense / income / transfer / savings / ignored" }
    expose :color,     documentation: { type: String }
    expose :icon,      documentation: { type: String }
    expose :essential, documentation: { type: "Boolean" }
    expose :position,  documentation: { type: Integer }
    expose :archived_at, documentation: { type: String, desc: "ISO 8601 or null when active" }
    expose :parent_path, documentation: { type: String, desc: "ltree path of the parent; null for top-level" } do |c|
      segments = c.path.to_s.split(".")
      segments.size > 1 ? segments[0..-2].join(".") : nil
    end
  end
end
