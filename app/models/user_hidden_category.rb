# frozen_string_literal: true

# Per-user join: which categories the user has marked "private". Owned
# by User (User#hidden_categories). Always-on — the act of selecting a
# category here triggers server-side bullet rendering everywhere it
# would otherwise render its name. Independent of the topbar
# privacy_mode cookie (that one masks all `.sensitive` content for
# screen-share; this one targets specific categories regardless of mode).
class UserHiddenCategory < ApplicationRecord
  belongs_to :user
  belongs_to :category

  validates :category_id, uniqueness: { scope: :user_id }
end
