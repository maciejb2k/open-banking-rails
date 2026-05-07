# frozen_string_literal: true

module Entities
  class Pagination < Grape::Entity
    expose :page,  documentation: { type: Integer }
    expose :limit, documentation: { type: Integer }
    expose :count, documentation: { type: Integer, desc: "Total rows across all pages" }
    expose :pages, documentation: { type: Integer, desc: "Total pages" }
  end
end
