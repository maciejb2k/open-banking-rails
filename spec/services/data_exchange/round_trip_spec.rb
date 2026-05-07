# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataExchange::Operations do
  it "round-trips a TPP credential + bank connection + bank account through Export → wipe → Import as the same user (permutation 7)" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user, name: "Source TPP")
    connection = create(:bank_connection, tpp_credential: tpp, bank_name: "Source Bank", bank_slug: "source_bank")
    create(:bank_account, tpp_credential: tpp, current_bank_connection: connection, currency: "PLN", iban: "PL61109010140000071219812874", name: "Source Acct", uid: "round-trip-uid-1")

    export = DataExchange::Operations::Export.call(
      user: user,
      resource_keys: [ :tpp_credentials, :bank_connections, :bank_accounts ],
      passphrase: "secret-pass-1234"
    )
    expect(export.run.status).to eq("succeeded")

    BankAccount.where(tpp_credential_id: user.tpp_credentials.select(:id)).delete_all
    BankConnection.where(tpp_credential_id: user.tpp_credentials.select(:id)).delete_all
    user.tpp_credentials.delete_all

    import = DataExchange::Operations::Import.call(
      user: user,
      bundle_blob: export.blob,
      passphrase: "secret-pass-1234",
      strategy: :skip_existing
    )

    expect(import.run.status).to eq("succeeded")
    user.reload
    expect(user.tpp_credentials.where(name: "Source TPP").count).to eq(1)
    expect(user.tpp_credentials.first.bank_connections.where(bank_slug: "source_bank").count).to eq(1)
    imported_account = BankAccount.find_by(uid: "round-trip-uid-1")
    expect(imported_account).to be_present
    expect(imported_account.name).to eq("Source Acct")
    expect(imported_account.currency).to eq("PLN")
    expect(imported_account.tpp_credential.user).to eq(user)
  end

  it "skip_existing on a re-import with the same data leaves counts unchanged" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user, name: "Source TPP")
    create(:bank_connection, tpp_credential: tpp, bank_slug: "source_bank")

    export = DataExchange::Operations::Export.call(user: user, resource_keys: [ :tpp_credentials, :bank_connections ], passphrase: "p")
    counts_before = { tpp: user.tpp_credentials.count, conn: BankConnection.where(tpp_credential_id: user.tpp_credentials.select(:id)).count }

    DataExchange::Operations::Import.call(user: user, bundle_blob: export.blob, passphrase: "p", strategy: :skip_existing)

    expect(user.tpp_credentials.count).to eq(counts_before[:tpp])
    expect(BankConnection.where(tpp_credential_id: user.tpp_credentials.select(:id)).count).to eq(counts_before[:conn])
  end

  it "rejects an Import with the wrong passphrase before creating any OperationRun (audit hygiene)" do
    source_user = create(:user)
    tpp = create(:tpp_credential, user: source_user)
    create(:bank_connection, tpp_credential: tpp)

    export = DataExchange::Operations::Export.call(
      user: source_user, resource_keys: [ :tpp_credentials, :bank_connections ], passphrase: "right-pass"
    )

    target_user = create(:user)
    runs_before = OperationRun.where(kind: DataExchange::Operations::Import::KIND, triggered_by_user: target_user).count

    expect {
      DataExchange::Operations::Import.call(user: target_user, bundle_blob: export.blob, passphrase: "wrong-pass")
    }.to raise_error(DataExchange::Operations::Import::Failed)

    expect(OperationRun.where(kind: DataExchange::Operations::Import::KIND, triggered_by_user: target_user).count).to eq(runs_before)
  end

  it "rejects Export with no resource_keys or no passphrase via Failed" do
    user = create(:user)

    expect { DataExchange::Operations::Export.call(user: user, resource_keys: [], passphrase: "x") }.to raise_error(DataExchange::Operations::Export::Failed, /no resources/)
    expect { DataExchange::Operations::Export.call(user: user, resource_keys: [ :tpp_credentials ], passphrase: "") }.to raise_error(DataExchange::Operations::Export::Failed, /passphrase/)
  end

  it "rejects Import with an unknown strategy or empty bundle blob via Failed" do
    user = create(:user)

    expect { DataExchange::Operations::Import.call(user: user, bundle_blob: "any", passphrase: "x", strategy: :wibble) }.to raise_error(DataExchange::Operations::Import::Failed, /unknown strategy/)
    expect { DataExchange::Operations::Import.call(user: user, bundle_blob: "", passphrase: "x") }.to raise_error(DataExchange::Operations::Import::Failed, /empty/)
  end
end
