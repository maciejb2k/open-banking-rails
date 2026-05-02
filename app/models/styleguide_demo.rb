# frozen_string_literal: true

class StyleguideDemo
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :email, :string
  attribute :category_id, :integer
end
