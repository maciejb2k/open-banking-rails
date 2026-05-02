# frozen_string_literal: true

# == Schema Information
#
# Table name: categories
#
#  id          :bigint           not null, primary key
#  archived_at :datetime
#  color       :string
#  essential   :boolean          default(FALSE), not null
#  icon        :string
#  kind        :string           default("expense"), not null
#  name        :string           not null
#  path        :ltree
#  position    :integer          default(0), not null
#  slug        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_categories_on_archived_at       (archived_at)
#  index_categories_on_path              (path) USING gist
#  index_categories_on_path_unique       (path) UNIQUE
#  index_categories_on_user_id           (user_id)
#  index_categories_on_user_id_and_slug  (user_id,slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Category < ApplicationRecord
  # Hierarchical, soft-deletable category — Layer 1 of the three-layer category
  # model. Backed by PG `ltree` (`path` column) with a GiST index, so subtree
  # containment queries hit native operators:
  #
  #   Category.under_path("food")               # food + every descendant
  #   Category.where("path ~ 'food.*{1}'")      # direct children only
  #   Category.where("nlevel(path) = 1")        # roots
  #
  # Layers 2/3 ride alongside:
  #   * `essential` (here)             — needs vs wants
  #   * `recurring` (Enrichment)       — cyclical charges as a property
  #   * `gutentag tags` (Enrichment)   — free-form labels
  #
  # `slug` stays stable across renames — used by seeds, exports, the LLM
  # merchant suggester, and merchant_rules. Slug uniqueness is per user.
  # `path` is the canonical lookup ("food.cooking.supermarket"); slug is the
  # leaf-only segment.
  #
  # `kind` (expense/income/transfer/savings/ignored) is the sign-convention
  # property analytics scopes partition on, orthogonal to path depth.

  KINDS = %w[expense income transfer savings ignored].freeze
  SEPARATOR = "."

  belongs_to :user
  has_many :merchants, foreign_key: :default_category_id, dependent: :nullify
  has_many :transaction_enrichments, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id },
                   format: { with: /\A[a-z0-9_\-]+\z/, message: "must be lowercase letters, digits, underscores, dashes" }
  validates :kind, inclusion: { in: KINDS }
  validates :path, presence: true, uniqueness: true

  before_validation :ensure_path_ends_with_slug

  scope :active,    -> { where(archived_at: nil) }
  scope :archived,  -> { where.not(archived_at: nil) }
  scope :ordered,   -> { order(Arel.sql("path::text")) }
  scope :for_user,  ->(user) { where(user_id: user.id) }
  scope :essential, -> { where(essential: true) }
  scope :roots,     -> { where("nlevel(path) = 1") }

  # Subtree containment via ltree `<@`. Pass a Category, a path string
  # ("food.cooking"), or an array of either.
  scope :under_path, ->(path_or_paths) {
    paths = Array(path_or_paths).map { |p| p.is_a?(Category) ? p.path : p.to_s }
    return none if paths.empty?
    where(paths.map { "path <@ ?" }.join(" OR "), *paths)
  }

  def archived? = archived_at.present?
  def unarchive! = update!(archived_at: nil)

  def archive!
    update!(archived_at: Time.current) unless archived?
  end

  # Self + descendants — returns an AR relation.
  def self_and_descendants
    self.class.where("path <@ ?", path)
  end

  # Just descendants (excludes self).
  def descendants
    self.class.where("path <@ ? AND path != ?", path, path)
  end

  # Direct children — `path` exactly one level deeper.
  def children
    self.class.where("path ~ ?::lquery", "#{path}.*{1}")
  end

  # Strict ancestors — every node whose path is a prefix of self.path.
  def ancestors
    return self.class.none if depth.zero?
    self.class.where("path @> ? AND path != ?", path, path)
  end

  # Direct parent (or nil for roots).
  def parent
    return nil if depth.zero?
    parent_path = path.split(SEPARATOR)[0..-2].join(SEPARATOR)
    self.class.find_by(path: parent_path)
  end

  # 0 for a root, 1 for a direct child, etc. Read from PG via `nlevel`
  # rather than counting dots in Ruby — keeps the source of truth in one
  # place and matches what `WHERE nlevel(path) = ?` returns.
  def depth
    @depth ||= path.to_s.count(SEPARATOR)
  end

  def root? = depth.zero?

  # Display: ["Food", "Cooking", "Supermarket"]. For breadcrumbs / pickers.
  # One query for the whole chain.
  def breadcrumb_names
    chain = ancestors.order(Arel.sql("nlevel(path)")) + [ self ]
    chain.map(&:name)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name slug kind essential archived_at created_at updated_at path]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[merchants transaction_enrichments]
  end

  private

  # `path` is the source of truth — but we accept `slug` set by callers and
  # auto-derive the path's leaf segment if missing. Seeds set `path`
  # directly; admin form sets `parent_path` + `slug` and we compose.
  def ensure_path_ends_with_slug
    return if path.blank?
    segments = path.to_s.split(SEPARATOR)
    return if slug == segments.last
    self.slug = segments.last if slug.blank?
  end
end
