# frozen_string_literal: true

# Hierarchical, soft-deletable category for transaction analytics.
#
# Two-level practical depth (top-level → sub-category) but the schema doesn't
# enforce it; callers querying "all leaves under X" should use #self_and_descendants.
#
# `slug` is stable across renames — used by seeds, exports, and any rule
# generator referencing categories by name.
class Category < ApplicationRecord
  KINDS = %w[expense income transfer savings ignored].freeze

  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: :parent_id, dependent: :restrict_with_error
  has_many :merchants, foreign_key: :default_category_id, dependent: :nullify
  has_many :transaction_enrichments, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9_\-]+\z/, message: "must be lowercase letters, digits, underscores, dashes" }
  validates :kind, inclusion: { in: KINDS }
  validate  :parent_must_be_top_level
  validate  :no_self_reference

  scope :active,    -> { where(archived_at: nil) }
  scope :archived,  -> { where.not(archived_at: nil) }
  scope :top_level, -> { where(parent_id: nil) }
  scope :ordered,   -> { order(position: :asc, name: :asc) }

  def archived? = archived_at.present?
  def unarchive! = update!(archived_at: nil)

  def archive!
    update!(archived_at: Time.current) unless archived?
  end

  def self_and_descendants
    Category.where(id: id).or(Category.where(parent_id: id))
  end

  private

  # We intentionally cap practical depth at 2 levels — top-level groups and
  # one layer of sub-categories. Deeper hierarchies make spend reports
  # confusing without adding analytical value.
  def parent_must_be_top_level
    return if parent_id.blank?
    return if parent && parent.parent_id.nil?
    errors.add(:parent_id, "must reference a top-level category")
  end

  def no_self_reference
    errors.add(:parent_id, "cannot reference self") if parent_id.present? && parent_id == id
  end
end
