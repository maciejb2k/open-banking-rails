# frozen_string_literal: true

# Plain ActiveModel object used by the admin styleguide to demo form components.
# Has no database table.
class StyleguideDemo
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :email, :string
end
