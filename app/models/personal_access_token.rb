# frozen_string_literal: true

# == Schema Information
#
# Table name: personal_access_tokens
#
#  id           :bigint           not null, primary key
#  last_four    :string(4)        not null
#  last_used_at :datetime
#  name         :string           not null
#  revoked_at   :datetime
#  token_digest :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_personal_access_tokens_on_token_digest      (token_digest) UNIQUE
#  index_personal_access_tokens_on_user_id           (user_id)
#  index_personal_access_tokens_on_user_id_and_name  (user_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class PersonalAccessToken < ApplicationRecord
  PREFIX     = "obrl_"
  RAW_BYTES  = 32
  NAME_RANGE = (1..50).freeze

  belongs_to :user

  validates :name, presence: true,
                   length: { in: NAME_RANGE },
                   uniqueness: { scope: :user_id, case_sensitive: false }
  validates :token_digest, presence: true, uniqueness: true
  validates :last_four, presence: true, length: { is: 4 }

  scope :active,  -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  def revoked?
    revoked_at.present?
  end

  # update_columns skips callbacks + paper_trail; this fires on every API call.
  def touch_used!(at: Time.current)
    update_columns(last_used_at: at, updated_at: at)
  end

  def self.digest_for(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end
end
