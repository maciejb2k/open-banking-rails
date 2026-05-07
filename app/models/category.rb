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
#  index_categories_on_user_id           (user_id)
#  index_categories_on_user_id_and_path  (user_id,path) UNIQUE
#  index_categories_on_user_id_and_slug  (user_id,slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Category < ApplicationRecord
  # Hierarchical, soft-deletable. Backed by PG `ltree` with a GiST index.
  # `slug` is the leaf-only segment (stable across renames, per-user unique);
  # `path` is the canonical lookup ("food.cooking.supermarket"). `kind` is
  # the sign-convention property analytics scopes partition on.

  KINDS = %w[expense income transfer savings ignored].freeze
  SEPARATOR = "."
  # PG ltree labels are [A-Za-z0-9_]+; we lowercase by convention. Without a
  # format gate here the uniqueness validator's SELECT casts a malformed
  # value to ::ltree and raises PG::SyntaxError before the slug format
  # validator gets to add a friendly error - so the controller would see a
  # 500 instead of a 422.
  LTREE_PATH_FORMAT = /\A[a-z0-9_]+(\.[a-z0-9_]+)*\z/

  belongs_to :user
  has_many :merchants, foreign_key: :default_category_id, dependent: :nullify
  has_many :transaction_enrichments, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id },
                   format: { with: /\A[a-z0-9_\-]+\z/, message: "must be lowercase letters, digits, underscores, dashes" }
  validates :kind, inclusion: { in: KINDS }
  validates :path, presence: true,
                   format: { with: LTREE_PATH_FORMAT, message: "must be lowercase letters, digits, underscores, dot-separated" }
  validates :path, uniqueness: { scope: :user_id }, if: :path_ltree_compatible?

  before_validation :ensure_path_ends_with_slug

  scope :active,    -> { where(archived_at: nil) }
  scope :archived,  -> { where.not(archived_at: nil) }
  scope :ordered,   -> { order(Arel.sql("path::text")) }
  scope :for_user,  ->(user) { where(user_id: user.id) }
  scope :essential, -> { where(essential: true) }
  scope :roots,     -> { where("nlevel(path) = 1") }

  # Accepts a Category, a path string, or an array of either.
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

  def self_and_descendants
    self.class.where("path <@ ?", path)
  end

  def descendants
    self.class.where("path <@ ? AND path != ?", path, path)
  end

  def children
    self.class.where("path ~ ?::lquery", "#{path}.*{1}")
  end

  def ancestors
    return self.class.none if depth.zero?
    self.class.where("path @> ? AND path != ?", path, path)
  end

  def parent
    return nil if depth.zero?
    parent_path = path.split(SEPARATOR)[0..-2].join(SEPARATOR)
    self.class.find_by(path: parent_path)
  end

  def depth
    @depth ||= path.to_s.count(SEPARATOR)
  end

  def root? = depth.zero?

  def in_use?
    descendants.exists? || merchants.exists? || transaction_enrichments.exists?
  end

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

  def path_ltree_compatible?
    path.to_s.match?(LTREE_PATH_FORMAT)
  end

  def ensure_path_ends_with_slug
    return if path.blank?
    segments = path.to_s.split(SEPARATOR)
    return if slug == segments.last
    self.slug = segments.last if slug.blank?
  end
end
