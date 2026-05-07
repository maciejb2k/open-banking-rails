# frozen_string_literal: true

# == Schema Information
#
# Table name: bank_connections
#
#  id                  :bigint           not null, primary key
#  access_balances     :boolean          default(TRUE), not null
#  access_transactions :boolean          default(TRUE), not null
#  authorized_at       :datetime
#  bank_country        :string           default("PL")
#  bank_name           :string
#  bank_slug           :string           not null
#  closed_at           :datetime
#  last_error          :text
#  last_refreshed_at   :datetime
#  last_synced_at      :datetime
#  psu_id_hash         :text
#  psu_type            :string           default("personal")
#  raw_session_payload :text
#  status              :string           default("pending"), not null
#  valid_until         :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  replaces_id         :bigint
#  session_id          :text
#  tpp_credential_id   :bigint           not null
#
# Indexes
#
#  index_bank_connections_lookup                (tpp_credential_id,bank_slug,status)
#  index_bank_connections_on_replaces_id        (replaces_id)
#  index_bank_connections_on_status             (status)
#  index_bank_connections_on_tpp_credential_id  (tpp_credential_id)
#  index_bank_connections_on_valid_until        (valid_until)
#
# Foreign Keys
#
#  fk_rails_...  (replaces_id => bank_connections.id)
#  fk_rails_...  (tpp_credential_id => tpp_credentials.id)
#
require "rails_helper"

RSpec.describe BankConnection do
  it "treats blank, future, and past valid_until correctly in expired?" do
    expect(build(:bank_connection, valid_until: nil).expired?).to be(false)
    expect(build(:bank_connection, valid_until: 1.day.from_now).expired?).to be(false)
    expect(build(:bank_connection, valid_until: 1.minute.ago).expired?).to be(true)
  end

  it "evaluates expiring_soon? on the within window with sensible defaults" do
    expect(build(:bank_connection, valid_until: nil).expiring_soon?).to be(false)
    expect(build(:bank_connection, valid_until: 3.days.from_now).expiring_soon?(within: 7.days)).to be(true)
    expect(build(:bank_connection, valid_until: 30.days.from_now).expiring_soon?(within: 7.days)).to be(false)
  end

  it "maps status_tone correctly across statuses including the authorized + expiring branch" do
    far = build(:bank_connection, status: "authorized", valid_until: 90.days.from_now)
    soon = build(:bank_connection, status: "authorized", valid_until: 3.days.from_now)
    pending = build(:bank_connection, status: "pending",  valid_until: 30.days.from_now)
    revoked = build(:bank_connection, status: "revoked",  valid_until: nil)
    expired = build(:bank_connection, status: "expired",  valid_until: 1.day.ago)
    replaced = build(:bank_connection, status: "replaced", valid_until: nil)

    expect(far.status_tone).to eq(:success)
    expect(soon.status_tone).to eq(:warning)
    expect(pending.status_tone).to eq(:info)
    expect(revoked.status_tone).to eq(:danger)
    expect(expired.status_tone).to eq(:danger)
    expect(replaced.status_tone).to eq(:muted)
  end

  it "computes days_until_expiry as an integer for set valid_until and nil for blank" do
    expect(build(:bank_connection, valid_until: nil).days_until_expiry).to be_nil

    soon = build(:bank_connection, valid_until: 3.days.from_now + 30.minutes)
    expect(soon.days_until_expiry).to eq(3)

    past = build(:bank_connection, valid_until: 2.days.ago)
    expect(past.days_until_expiry).to be < 0
  end

  it "isolates connections per user via for_user(user)" do
    user_a = create(:user)
    user_b = create(:user)
    tpp_a = create(:tpp_credential, user: user_a)
    tpp_b = create(:tpp_credential, user: user_b)
    conn_a = create(:bank_connection, tpp_credential: tpp_a)
    conn_b = create(:bank_connection, tpp_credential: tpp_b)

    expect(described_class.for_user(user_a).pluck(:id)).to contain_exactly(conn_a.id)
    expect(described_class.for_user(user_b).pluck(:id)).to contain_exactly(conn_b.id)
  end

  it "excludes inactive connections from expiring_within even when their valid_until is in the window" do
    tpp = create(:tpp_credential)
    active_soon  = create(:bank_connection, :active,  tpp_credential: tpp, valid_until: 3.days.from_now)
    expired_soon = create(:bank_connection, :expired, tpp_credential: tpp, valid_until: 3.days.from_now)

    ids = described_class.expiring_within(7.days).pluck(:id)
    expect(ids).to include(active_soon.id)
    expect(ids).not_to include(expired_soon.id)
  end

  it "round-trips encrypted session_id with the raw column not containing the plaintext" do
    conn = create(:bank_connection, session_id: "session-secret-12345")
    conn.reload

    expect(conn.session_id).to eq("session-secret-12345")
    expect_encrypted_at_rest(conn, :session_id, "session-secret-12345")
  end
end
