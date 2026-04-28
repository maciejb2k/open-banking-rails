# frozen_string_literal: true

# Form-only object backing the "Add bank" UI. Carries user input through
# the new/create cycle so shared form/* components (which expect form.object)
# work uniformly. Not an AR model — never persisted.
class BankConnectionRequestForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :aspsp_name, :string
  attribute :aspsp_country, :string, default: "PL"
  attribute :psu_type, :string, default: "personal"
  attribute :valid_days, :integer, default: 180

  validates :aspsp_name, presence: true
  validates :aspsp_country, presence: true
  validates :psu_type, inclusion: { in: %w[personal business] }
  validates :valid_days, numericality: { greater_than: 0, less_than_or_equal_to: 180 }
end
