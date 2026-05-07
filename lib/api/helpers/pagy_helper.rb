# frozen_string_literal: true

module Helpers
  module PagyHelper
    extend Grape::API::Helpers
    include ::Pagy::Method

    def paginate(collection, **)
      pagy_obj, records = pagy(:offset, collection, **)
      pagy_obj.headers_hash.each { |key, value| header key, value }
      [ pagy_obj, records ]
    end

    def pagination_meta(pagy_obj)
      {
        page:  pagy_obj.page,
        limit: pagy_obj.limit,
        count: pagy_obj.count,
        pages: pagy_obj.pages
      }
    end
  end
end
