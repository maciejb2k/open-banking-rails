# frozen_string_literal: true

require "rails_helper"

RSpec.describe PersonalAccessToken do
  it "rejects a second insert with a duplicate token_digest at the database level" do
    user = create(:user)
    digest = described_class.digest_for("obrl_shared")
    described_class.create!(user: user, name: "first", token_digest: digest, last_four: "ared")

    expect {
      described_class.create!(user: user, name: "second", token_digest: digest, last_four: "ared")
    }.to raise_error(ActiveRecord::RecordInvalid, /Token digest has already been taken/)
  end

  it "rejects a second token with a name that case-insensitively matches an existing one for the same user" do
    user = create(:user)
    create(:personal_access_token, user: user, name: "Laptop")

    duplicate = build(:personal_access_token, user: user, name: "laptop")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to include("has already been taken")
  end

  it "lets two different users use the same token name" do
    user_a = create(:user)
    user_b = create(:user)
    create(:personal_access_token, user: user_a, name: "laptop")

    expect {
      create(:personal_access_token, user: user_b, name: "laptop")
    }.to change(described_class, :count).by(1)
  end

  it "computes digest_for as a deterministic SHA-256 of the input" do
    expected = Digest::SHA256.hexdigest("obrl_test")
    expect(described_class.digest_for("obrl_test")).to eq(expected)
    expect(described_class.digest_for("obrl_test")).to eq(described_class.digest_for("obrl_test"))
  end

  it "never persists the raw obrl_-prefixed string in the token_digest column" do
    user = create(:user)
    raw = "obrl_supersecretrawtokenvalue"
    pat = described_class.create!(
      user: user,
      name: "raw-secrecy",
      token_digest: described_class.digest_for(raw),
      last_four: raw.last(4)
    )

    raw_column = ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_for_conditions([ "SELECT token_digest FROM personal_access_tokens WHERE id = ?", pat.id ])
    )
    expect(raw_column).not_to include("obrl_")
    expect(raw_column).to eq(described_class.digest_for(raw))
  end

  it "bumps last_used_at via touch_used! without firing after_save / after_commit callbacks" do
    user = create(:user)
    pat = create(:personal_access_token, user: user)
    callback_count = 0
    described_class.set_callback(:save, :after) { callback_count += 1 }

    begin
      pat.touch_used!(at: 1.minute.from_now)
    ensure
      described_class.reset_callbacks(:save)
    end

    expect(pat.reload.last_used_at).to be_within(2.seconds).of(1.minute.from_now)
    expect(callback_count).to eq(0)
  end

  it "does not create a PaperTrail version on touch_used! even when versioning is on", :papertrail do
    user = create(:user)
    pat = create(:personal_access_token, user: user)

    PaperTrail.request(enabled: true) do
      expect { pat.touch_used!(at: Time.current) }.not_to change(PaperTrail::Version, :count)
    end
  end

  it "partitions rows correctly across active and revoked scopes when revoked_at flips" do
    user = create(:user)
    active_pat = create(:personal_access_token, user: user)
    revoked_pat = create(:personal_access_token, :revoked, user: user)

    expect(described_class.active.pluck(:id)).to contain_exactly(active_pat.id)
    expect(described_class.revoked.pluck(:id)).to contain_exactly(revoked_pat.id)

    active_pat.update!(revoked_at: Time.current)
    expect(described_class.active.pluck(:id)).to be_empty
    expect(described_class.revoked.pluck(:id)).to contain_exactly(active_pat.id, revoked_pat.id)
  end

  it "destroys all of a user's tokens when the user is destroyed (dependent destroy)" do
    user = create(:user)
    create_list(:personal_access_token, 3, user: user)

    expect { user.destroy }.to change(described_class, :count).by(-3)
  end
end
