class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  validates :name, presence: true

  def initials
    return "?" if name.blank?

    name.split(/\s+/).first(2).map { |part| part[0]&.upcase }.join
  end

  def display_name
    name.presence || email
  end
end
