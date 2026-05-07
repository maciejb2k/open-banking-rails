# frozen_string_literal: true

require "rails_helper"

RSpec.describe TppCredential do
  def build_pem(not_after: 1.year.from_now)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 0x12345
    cert.subject = OpenSSL::X509::Name.parse("/CN=Test TPP")
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = 1.day.ago
    cert.not_after = not_after
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert.to_pem
  end

  it "extracts cert_expires_at from a valid public_cert_pem on save" do
    not_after = 1.year.from_now
    cred = build(:tpp_credential, public_cert_pem: build_pem(not_after: not_after))

    cred.save!

    expect(cred.cert_expires_at).to be_within(1.second).of(not_after)
  end

  it "leaves cert_expires_at nil when public_cert_pem is blank" do
    cred = build(:tpp_credential, public_cert_pem: nil)

    cred.save!

    expect(cred.cert_expires_at).to be_nil
  end

  it "does not raise on garbage PEM and leaves cert_expires_at nil" do
    cred = build(:tpp_credential, public_cert_pem: "-----BEGIN CERTIFICATE-----\nNOT A CERT\n-----END CERTIFICATE-----")

    expect { cred.save! }.not_to raise_error
    expect(cred.cert_expires_at).to be_nil
  end

  it "returns a populated cert_info hash for a valid PEM and nil on garbage or blank" do
    cred = create(:tpp_credential, public_cert_pem: build_pem)

    info = cred.cert_info
    expect(info).to include(:subject, :issuer, :not_before, :not_after, :days_remaining, :serial, :signature_algorithm, :key_size)
    expect(info[:days_remaining]).to be >= 0
    expect(info[:key_size]).to eq(2048)

    cred.update_columns(public_cert_pem: nil)
    expect(cred.cert_info).to be_nil

    cred.update_columns(public_cert_pem: "garbage")
    expect(cred.cert_info).to be_nil
  end

  it "evaluates cert_expired? on the cert_expires_at boundary" do
    expect(build(:tpp_credential, cert_expires_at: nil).cert_expired?).to be(false)
    expect(build(:tpp_credential, cert_expires_at: 1.day.from_now).cert_expired?).to be(false)
    expect(build(:tpp_credential, cert_expires_at: 1.minute.ago).cert_expired?).to be(true)
  end

  it "evaluates cert_expiring_soon? against the configured window" do
    expect(build(:tpp_credential, cert_expires_at: nil).cert_expiring_soon?).to be(false)
    expect(build(:tpp_credential, cert_expires_at: 3.days.from_now).cert_expiring_soon?(within: 7.days)).to be(true)
    expect(build(:tpp_credential, cert_expires_at: 30.days.from_now).cert_expiring_soon?(within: 7.days)).to be(false)
  end

  it "atomically transfers the primary flag via make_primary! leaving exactly one primary per user" do
    user = create(:user)
    first = create(:tpp_credential, user: user, primary: true)
    second = create(:tpp_credential, user: user, primary: false)

    second.make_primary!

    expect(first.reload.primary).to be(false)
    expect(second.reload.primary).to be(true)
    expect(user.tpp_credentials.where(primary: true).count).to eq(1)
  end

  it "surfaces a friendly :primary error when a second primary credential is built for the same user" do
    user = create(:user)
    create(:tpp_credential, user: user, primary: true)

    second = build(:tpp_credential, user: user, primary: true)

    expect(second).not_to be_valid
    expect(second.errors[:primary].join).to include("already primary")
  end

  it "round-trips application_id and private_key_pem through Rails encryption with the raw columns not equal to plaintext" do
    pem = OpenSSL::PKey::RSA.new(2048).to_pem
    cred = create(:tpp_credential, application_id: "app-secret-123", private_key_pem: pem)
    cred.reload

    expect(cred.application_id).to eq("app-secret-123")
    expect(cred.private_key_pem).to eq(pem)
    expect_encrypted_at_rest(cred, :application_id, "app-secret-123")
    expect_encrypted_at_rest(cred, :private_key_pem, pem)
  end

  it "skips application_id and private_key_pem from PaperTrail object_changes when versioned", :papertrail do
    cred = create(:tpp_credential, application_id: "app-1", private_key_pem: OpenSSL::PKey::RSA.new(2048).to_pem)

    PaperTrail.request(enabled: true) do
      cred.update!(name: "Renamed TPP", application_id: "app-2")
    end

    version = cred.versions.last
    changes_blob = version.object_changes.to_s
    expect(changes_blob).not_to include("app-2")
    expect(changes_blob).not_to include("BEGIN RSA PRIVATE KEY")
    expect(changes_blob).to include("Renamed TPP")
  end
end
